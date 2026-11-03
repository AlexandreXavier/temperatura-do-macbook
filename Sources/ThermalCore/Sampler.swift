import Darwin
import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt

/// Reads every metric. Not thread-safe: use it from a single queue.
public final class Sampler {
    /// SMC keys of the sensors shown in the app, in display order. Absent keys are skipped.
    static let sensorCatalog: [(key: String, name: String)] = [
        ("TCXC", "CPU (PECI)"), ("TC1C", "Núcleo 1"), ("TC2C", "Núcleo 2"), ("TC3C", "Núcleo 3"), ("TC4C", "Núcleo 4"),
        ("TCGC", "GPU integrada"), ("TC0P", "Junto ao CPU"), ("Th1H", "Dissipador esq."), ("Th2H", "Dissipador dir."),
        ("TM0P", "Memória"), ("TPCD", "Chipset"), ("TH0V", "SSD"), ("TW0P", "Wi-Fi"), ("TB0T", "Bateria"),
        ("Ts0P", "Apoio de pulso"), ("Ta0P", "Ar interno"),
    ]
    static let cpuKeys = ["TCXC", "TC0F", "TC0E", "TC0D", "TC0P"]

    private let smc: SMCClient?
    private var previousTicks: [UInt32]?
    private var fanCount: Int?

    public var isSupported: Bool { smc != nil }

    public init() { smc = SMCClient() }

    /// Fast part of a reading: only sensors and kernel counters, no child processes.
    public func sample() -> Snapshot {
        var s = Snapshot()
        readSensors(into: &s)
        s.cpuUsage = readCPUUsage()
        var load = [0.0, 0.0, 0.0]
        if getloadavg(&load, 3) > 0 { s.loadAverage = load[0] }
        s.swapUsedGB = Self.readSwapGB()
        s.speedLimit = Self.readSpeedLimit()
        return s
    }

    private func readSensors(into s: inout Snapshot) {
        guard let smc else { return }
        s.sensors = Self.sensorCatalog.compactMap { key, name in
            guard let value = smc.read(key), SMCDecoder.isPlausibleTemperature(value) else { return nil }
            return SensorReading(key: key, name: name, celsius: value)
        }
        for key in Self.cpuKeys {
            if let value = smc.read(key), SMCDecoder.isPlausibleTemperature(value) {
                s.cpuCelsius = value
                break
            }
        }
        if fanCount == nil { fanCount = smc.read("FNum").map { Int($0) } ?? 0 }
        s.fans = (0..<(fanCount ?? 0)).compactMap { index in
            guard let rpm = smc.read("F\(index)Ac") else { return nil }
            return FanReading(
                index: index, rpm: rpm,
                minRPM: smc.read("F\(index)Mn") ?? 0,
                maxRPM: smc.read("F\(index)Mx") ?? 0
            )
        }
        s.power = PowerReading(
            package: smc.read("PCPT"), cores: smc.read("PCPC"),
            graphics: smc.read("PCPG"), system: smc.read("PSTR")
        )
    }

    private func readCPUUsage() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks
        let ticks = [t.0, t.1, t.2, t.3] // user, system, idle, nice
        defer { previousTicks = ticks }
        guard let previous = previousTicks else { return nil }
        let delta = zip(ticks, previous).map { Double($0 &- $1) }
        let total = delta.reduce(0, +)
        return total > 0 ? (total - delta[2]) / total * 100 : nil
    }

    private static func readSwapGB() -> Double? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return Double(usage.xsu_used) / 1_073_741_824
    }

    private static func readSpeedLimit() -> Int? {
        var status: Unmanaged<CFDictionary>?
        guard IOPMCopyCPUPowerStatus(&status) == kIOReturnSuccess,
              let dict = status?.takeRetainedValue() as? [String: Any] else { return nil }
        return dict[kIOPMCPUPowerLimitProcessorSpeedKey] as? Int
    }

    public static func readBattery() -> BatteryHealth? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = properties?.takeRetainedValue() as? [String: Any],
              let design = dict["DesignCapacity"] as? Int, design > 0,
              let maximum = (dict["AppleRawMaxCapacity"] ?? dict["MaxCapacity"]) as? Int else { return nil }
        return BatteryHealth(
            cycles: dict["CycleCount"] as? Int ?? 0,
            capacityPercent: Double(maximum) / Double(design) * 100,
            celsius: (dict["Temperature"] as? Int).map { Double($0) / 100 }
        )
    }

    /// Top processes by real CPU use over one second. Spawns `top`, the only unprivileged tool
    /// that sees kernel_task, so call it sparingly.
    public static func readTopProcesses() -> [ProcessLoad] {
        let top = Process()
        top.executableURL = URL(fileURLWithPath: "/usr/bin/top")
        top.arguments = ["-l", "2", "-s", "1", "-o", "cpu", "-n", "25", "-stats", "command,cpu"]
        let pipe = Pipe()
        top.standardOutput = pipe
        top.standardError = FileHandle.nullDevice
        guard (try? top.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        top.waitUntilExit()
        return TopParser.parse(String(decoding: data, as: UTF8.self))
    }
}

public enum TopParser {
    /// Parses the last sample of `top -stats command,cpu` and merges helpers into their app.
    public static func parse(_ output: String) -> [ProcessLoad] {
        let lines = output.components(separatedBy: "\n")
        guard let header = lines.lastIndex(where: { $0.hasPrefix("COMMAND") }) else { return [] }
        var totals: [String: Double] = [:]
        for line in lines[(header + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let split = trimmed.range(of: " ", options: .backwards) else { continue }
            let value = trimmed[split.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: "*"))
            guard let cpu = Double(value) else { continue }
            let name = appName(String(trimmed[..<split.lowerBound]).trimmingCharacters(in: .whitespaces))
            if name == "top" { continue }
            totals[name, default: 0] += cpu
        }
        return totals.map { ProcessLoad(name: $0.key, cpu: $0.value) }
            .sorted { $0.cpu == $1.cpu ? $0.name < $1.name : $0.cpu > $1.cpu }
    }

    /// `top` cuts names at 16 characters, so "Google Chrome He" must also match as a Helper.
    static func appName(_ command: String) -> String {
        command.replacingOccurrences(
            of: #"\s(H|He|Hel|Help|Helpe|Helper)(\s.*)?$"#, with: "", options: .regularExpression
        )
    }
}
