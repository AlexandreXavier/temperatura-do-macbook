import Foundation
import IOKit

/// Decoding of the fixed-point formats used by the SMC. Pure, so it can be tested without hardware.
public enum SMCDecoder {
    public static func decode(type: String, bytes: [UInt8]) -> Double? {
        let name = type.trimmingCharacters(in: .whitespaces)
        switch name {
        case "flt":
            guard bytes.count == 4 else { return nil }
            return Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
        case "ui8":
            return bytes.first.map(Double.init)
        case "ui16":
            guard bytes.count == 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        default:
            break
        }
        // "spXY" is signed and "fpXY" unsigned; Y (hex) is the number of fractional bits.
        guard bytes.count == 2, name.count == 4, let fraction = Int(String(name.last!), radix: 16) else {
            return nil
        }
        let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        let divisor = Double(1 << fraction)
        if name.hasPrefix("sp") { return Double(Int16(bitPattern: raw)) / divisor }
        if name.hasPrefix("fp") { return Double(raw) / divisor }
        return nil
    }

    /// Absent sensors report placeholders such as -127, -35 or 0.
    public static func isPlausibleTemperature(_ value: Double) -> Bool {
        value > 1 && value < 130
    }
}

/// Read-only access to the Intel Mac SMC. It never issues the write command, so fans
/// and thermal limits stay under macOS control.
public final class SMCClient {
    private struct Version { var a: UInt8 = 0, b: UInt8 = 0, c: UInt8 = 0, d: UInt8 = 0; var e: UInt16 = 0 }
    private struct PLimit { var a: UInt16 = 0, b: UInt16 = 0; var c: UInt32 = 0, d: UInt32 = 0, e: UInt32 = 0 }
    private struct KeyInfo { var size: UInt32 = 0; var type: UInt32 = 0; var attributes: UInt8 = 0 }
    private typealias Bytes32 = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )
    /// Mirrors the kernel's 80-byte SMCParamStruct.
    private struct Param {
        var key: UInt32 = 0
        var version = Version()
        var pLimit = PLimit()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var command: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes32 = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private static let handleYPCEvent: UInt32 = 2
    private static let commandRead: UInt8 = 5
    private static let commandKeyInfo: UInt8 = 9

    private var connection: io_connect_t = 0
    private var keyInfoCache: [UInt32: KeyInfo] = [:]

    public init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
    }

    deinit { IOServiceClose(connection) }

    public func read(_ key: String) -> Double? {
        let code = key.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        guard let info = keyInfo(code), info.size > 0, info.size <= 32 else { return nil }
        var input = Param()
        input.key = code
        input.keyInfo.size = info.size
        input.command = Self.commandRead
        guard let output = call(input) else { return nil }
        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(Int(info.size))) }
        return SMCDecoder.decode(type: Self.string(info.type), bytes: bytes)
    }

    private func keyInfo(_ code: UInt32) -> KeyInfo? {
        if let cached = keyInfoCache[code] { return cached }
        var input = Param()
        input.key = code
        input.command = Self.commandKeyInfo
        guard let output = call(input) else { return nil }
        keyInfoCache[code] = output.keyInfo
        return output.keyInfo
    }

    private func call(_ input: Param) -> Param? {
        var input = input
        var output = Param()
        var size = MemoryLayout<Param>.stride
        let status = IOConnectCallStructMethod(connection, Self.handleYPCEvent, &input, size, &output, &size)
        return status == KERN_SUCCESS && output.result == 0 ? output : nil
    }

    private static func string(_ code: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8(code >> UInt32($0) & 0xFF) }
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }
}
