import Foundation

public struct HistoryPoint: Identifiable, Equatable, Sendable {
    public let date: Date
    public let cpu: Double
    public let fanEffort: Double?
    public let packageWatts: Double?
    public var id: Date { date }

    public init(date: Date, cpu: Double, fanEffort: Double?, packageWatts: Double?) {
        self.date = date
        self.cpu = cpu
        self.fanEffort = fanEffort
        self.packageWatts = packageWatts
    }
}

/// In-memory timeline plus a CSV log that survives restarts.
/// Fine points cover the last hour; one averaged point per minute goes to disk and covers a week.
public final class History {
    public static let fineWindow: TimeInterval = 3600
    public static let retention: TimeInterval = 7 * 86400

    public private(set) var fine: [HistoryPoint] = []
    public private(set) var coarse: [HistoryPoint] = []
    private var bucket: [HistoryPoint] = []
    private let fileURL: URL?

    private static let header = "timestamp,cpu_c,fan_pct,package_w"

    public init(fileURL: URL?) {
        self.fileURL = fileURL
        load()
    }

    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Temperatura/historico.csv")
    }

    public func add(_ point: HistoryPoint) {
        fine.append(point)
        let cutoff = point.date.addingTimeInterval(-Self.fineWindow)
        if let first = fine.first, first.date < cutoff { fine.removeAll { $0.date < cutoff } }

        if let start = bucket.first?.date, point.date.timeIntervalSince(start) >= 60 { flushBucket() }
        bucket.append(point)
    }

    /// Points to draw for a time window, using the finest resolution available.
    public func points(lastSeconds window: TimeInterval, now: Date = Date()) -> [HistoryPoint] {
        let cutoff = now.addingTimeInterval(-window)
        let older = coarse.filter { $0.date < fine.first?.date ?? .distantFuture }
        return (older + fine).filter { $0.date >= cutoff }
    }

    public func flushBucket() {
        guard !bucket.isEmpty else { return }
        let average = History.average(bucket)
        bucket.removeAll()
        coarse.append(average)
        let cutoff = average.date.addingTimeInterval(-Self.retention)
        if let first = coarse.first, first.date < cutoff { coarse.removeAll { $0.date < cutoff } }
        append(average)
    }

    static func average(_ points: [HistoryPoint]) -> HistoryPoint {
        func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
        return HistoryPoint(
            date: points.last!.date,
            cpu: mean(points.map(\.cpu)) ?? 0,
            fanEffort: mean(points.compactMap(\.fanEffort)),
            packageWatts: mean(points.compactMap(\.packageWatts))
        )
    }

    private func append(_ p: HistoryPoint) {
        guard let fileURL else { return }
        func field(_ value: Double?) -> String { value.map { String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? "" }
        let line = "\(Int(p.date.timeIntervalSince1970)),\(field(p.cpu)),\(field(p.fanEffort)),\(field(p.packageWatts))\n"
        let manager = FileManager.default
        if !manager.fileExists(atPath: fileURL.path) {
            try? manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? (Self.header + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }

    private func load() {
        guard let fileURL, let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let cutoff = Date().addingTimeInterval(-Self.retention)
        coarse = text.split(separator: "\n").dropFirst().compactMap(Self.parse).filter { $0.date >= cutoff }
    }

    static func parse(_ line: Substring) -> HistoryPoint? {
        let fields = line.split(separator: ",", omittingEmptySubsequences: false)
        guard fields.count == 4, let time = Double(fields[0]), let cpu = Double(fields[1]) else { return nil }
        return HistoryPoint(
            date: Date(timeIntervalSince1970: time), cpu: cpu,
            fanEffort: Double(fields[2]), packageWatts: Double(fields[3])
        )
    }
}
