import Foundation

public struct SensorReading: Identifiable, Equatable, Sendable {
    public let key: String
    public let name: String
    public let celsius: Double
    public var id: String { key }

    public init(key: String, name: String, celsius: Double) {
        self.key = key
        self.name = name
        self.celsius = celsius
    }
}

public struct FanReading: Identifiable, Equatable, Sendable {
    public let index: Int
    public let rpm: Double
    public let minRPM: Double
    public let maxRPM: Double
    public var id: Int { index }

    public init(index: Int, rpm: Double, minRPM: Double, maxRPM: Double) {
        self.index = index
        self.rpm = rpm
        self.minRPM = minRPM
        self.maxRPM = maxRPM
    }

    /// 0 at the fan's resting speed, 100 at its maximum.
    public var effort: Double {
        guard maxRPM > minRPM else { return 0 }
        return min(100, max(0, (rpm - minRPM) / (maxRPM - minRPM) * 100))
    }
}

public struct PowerReading: Equatable, Sendable {
    public var package: Double?
    public var cores: Double?
    public var graphics: Double?
    public var system: Double?

    public init(package: Double? = nil, cores: Double? = nil, graphics: Double? = nil, system: Double? = nil) {
        self.package = package
        self.cores = cores
        self.graphics = graphics
        self.system = system
    }
}

public struct ProcessLoad: Identifiable, Equatable, Sendable {
    public let name: String
    public let cpu: Double
    public var id: String { name }

    public init(name: String, cpu: Double) {
        self.name = name
        self.cpu = cpu
    }
}

public struct BatteryHealth: Equatable, Sendable {
    public var cycles: Int
    public var capacityPercent: Double
    public var celsius: Double?

    public init(cycles: Int, capacityPercent: Double, celsius: Double?) {
        self.cycles = cycles
        self.capacityPercent = capacityPercent
        self.celsius = celsius
    }
}

/// Averages over the last minutes. Temperature lags power by a minute or more,
/// so comparing the two needs a sustained window rather than one reading.
public struct SustainedLoad: Equatable, Sendable {
    public var cpu: Double
    public var watts: Double
    public var fanEffort: Double?

    public init(cpu: Double, watts: Double, fanEffort: Double?) {
        self.cpu = cpu
        self.watts = watts
        self.fanEffort = fanEffort
    }

    public static let window: TimeInterval = 180

    /// Nil until most of the window is covered.
    public init?(recent points: [HistoryPoint], now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Self.window)
        let inside = points.filter { $0.date >= cutoff }
        let watts = inside.compactMap(\.packageWatts)
        guard let first = inside.first, now.timeIntervalSince(first.date) >= Self.window * 2 / 3,
              !watts.isEmpty else { return nil }
        let fans = inside.compactMap(\.fanEffort)
        self.cpu = inside.map(\.cpu).reduce(0, +) / Double(inside.count)
        self.watts = watts.reduce(0, +) / Double(watts.count)
        self.fanEffort = fans.isEmpty ? nil : fans.reduce(0, +) / Double(fans.count)
    }
}

public struct Snapshot: Equatable, Sendable {
    public var date = Date()
    public var sustained: SustainedLoad?
    public var cpuCelsius: Double?
    public var sensors: [SensorReading] = []
    public var fans: [FanReading] = []
    public var power = PowerReading()
    public var cpuUsage: Double?
    public var loadAverage: Double?
    public var coreCount = ProcessInfo.processInfo.activeProcessorCount
    public var swapUsedGB: Double?
    public var speedLimit: Int?
    public var processes: [ProcessLoad] = []
    public var battery: BatteryHealth?

    public init() {}

    public var fanEffort: Double? {
        fans.isEmpty ? nil : fans.map(\.effort).reduce(0, +) / Double(fans.count)
    }
}

public enum HeatLevel: Int, Comparable, Sendable {
    case normal, warm, hot, critical

    public init(celsius: Double) {
        switch celsius {
        case ..<70: self = .normal
        case ..<85: self = .warm
        case ..<95: self = .hot
        default: self = .critical
        }
    }

    public static func < (a: HeatLevel, b: HeatLevel) -> Bool { a.rawValue < b.rawValue }

    public var label: String {
        switch self {
        case .normal: return "Normal"
        case .warm: return "Morno"
        case .hot: return "Quente"
        case .critical: return "Crítico"
        }
    }
}
