import Foundation
import Testing
@testable import ThermalCore

@Suite struct DecoderTests {
    @Test func signedFixedPoint() {
        #expect(SMCDecoder.decode(type: "sp78", bytes: [0x42, 0x80]) == 66.5)
        #expect(SMCDecoder.decode(type: "sp78", bytes: [0x81, 0x00]) == -127)
    }

    @Test func fanFormat() {
        #expect(SMCDecoder.decode(type: "fpe2", bytes: [0x36, 0xC0]) == 3504)
    }

    // PCPL on this Mac reads [23, 128]: 47 W, the published TDP of the i7-4750HQ.
    @Test func powerFormat() {
        #expect(SMCDecoder.decode(type: "sp87", bytes: [23, 128]) == 47)
    }

    @Test func rejectsMalformedInput() {
        #expect(SMCDecoder.decode(type: "sp78", bytes: [1]) == nil)
        #expect(SMCDecoder.decode(type: "{fds", bytes: [1, 2]) == nil)
    }

    @Test func filtersAbsentSensors() {
        #expect(!SMCDecoder.isPlausibleTemperature(-127))
        #expect(!SMCDecoder.isPlausibleTemperature(0))
        #expect(SMCDecoder.isPlausibleTemperature(85))
    }
}

@Suite struct TopParserTests {
    static let output = """
    Processes: 1 total
    COMMAND          %CPU
    Old sample       99.0
    Processes: 1 total
    COMMAND          %CPU
    kernel_task      50.9
    Google Chrome    12.4
    Google Chrome He 4.2
    Claude Helper (R 3.1
    top              5.9
    """

    @Test func usesLastSampleAndMergesHelpers() {
        let loads = TopParser.parse(Self.output)
        #expect(loads.map(\.name) == ["kernel_task", "Google Chrome", "Claude"])
        #expect(abs(loads[1].cpu - 16.6) < 0.001)
    }

    @Test func keepsNamesThatOnlyLookLikeHelpers() {
        #expect(TopParser.appName("Hex Fiend") == "Hex Fiend")
        #expect(TopParser.appName("Google Chrome H") == "Google Chrome")
    }
}

@Suite struct DiagnosisTests {
    private func ids(_ s: Snapshot) -> [String] { Diagnosis.evaluate(s).map(\.id) }

    @Test func coolSystemHasNoFindings() {
        var s = Snapshot()
        s.cpuCelsius = 50
        s.power.package = 8
        #expect(ids(s).isEmpty)
    }

    @Test func sustainedHeatAtLowPowerSuspectsCooling() {
        var s = Snapshot()
        s.sustained = SustainedLoad(cpu: 80, watts: 15, fanEffort: 30)
        #expect(ids(s) == ["cooling"])
    }

    // Right after a load spike the die is still hot while power has already dropped.
    @Test func momentaryHeatAtLowPowerIsNotBlamedOnCooling() {
        var s = Snapshot()
        s.cpuCelsius = 80
        s.power.package = 12
        #expect(ids(s).isEmpty)
    }

    @Test func hotUnderHeavyPowerIsNotBlamedOnCooling() {
        var s = Snapshot()
        s.sustained = SustainedLoad(cpu: 90, watts: 45, fanEffort: 80)
        #expect(ids(s).isEmpty)
    }

    @Test func sustainedLoadNeedsMostOfTheWindow() {
        let now = Date()
        func point(_ age: TimeInterval) -> HistoryPoint {
            HistoryPoint(date: now.addingTimeInterval(-age), cpu: 80, fanEffort: 30, packageWatts: 15)
        }
        #expect(SustainedLoad(recent: [point(30), point(0)], now: now) == nil)
        let load = SustainedLoad(recent: [point(600), point(150), point(0)], now: now)
        #expect(load == SustainedLoad(cpu: 80, watts: 15, fanEffort: 30))
    }

    @Test func throttlingRanksFirst() {
        var s = Snapshot()
        s.speedLimit = 70
        s.swapUsedGB = 4
        #expect(ids(s) == ["throttle", "swap"])
    }

    @Test func kernelTaskIsNotReportedAsAnApp() {
        var s = Snapshot()
        s.processes = [ProcessLoad(name: "kernel_task", cpu: 60)]
        #expect(ids(s) == ["kernel"])
    }

    @Test func wornBatteryIsReported() {
        var s = Snapshot()
        s.battery = BatteryHealth(cycles: 2387, capacityPercent: 34.5, celsius: 30)
        #expect(ids(s) == ["battery"])
    }
}

@Suite struct HeatLevelTests {
    @Test func boundaries() {
        #expect(HeatLevel(celsius: 69.9) == .normal)
        #expect(HeatLevel(celsius: 70) == .warm)
        #expect(HeatLevel(celsius: 85) == .hot)
        #expect(HeatLevel(celsius: 95) == .critical)
    }
}

@Suite struct HistoryTests {
    private func point(_ seconds: TimeInterval, cpu: Double) -> HistoryPoint {
        HistoryPoint(date: Date(timeIntervalSince1970: seconds), cpu: cpu, fanEffort: nil, packageWatts: 10)
    }

    @Test func persistsMinuteAveragesAndReloads() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("h.csv")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let now = Date().timeIntervalSince1970
        let history = History(fileURL: url)
        history.add(point(now - 70, cpu: 60))
        history.add(point(now - 40, cpu: 80))
        history.add(point(now, cpu: 90)) // closes the first minute

        #expect(history.coarse.count == 1)
        #expect(history.coarse[0].cpu == 70)

        let reloaded = History(fileURL: url)
        #expect(reloaded.coarse.count == 1)
        #expect(reloaded.coarse[0].cpu == 70)
        #expect(reloaded.coarse[0].fanEffort == nil)
    }

    @Test func dropsFinePointsOlderThanAnHour() {
        let history = History(fileURL: nil)
        history.add(point(0, cpu: 50))
        history.add(point(3700, cpu: 60))
        #expect(history.fine.map(\.cpu) == [60])
    }
}
