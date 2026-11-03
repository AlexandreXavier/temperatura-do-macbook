import AppKit
import SwiftUI
import ThermalCore

enum Theme {
    static let series = Color(red: 0.30, green: 0.56, blue: 0.95)
    static let good = Color(red: 0.05, green: 0.64, blue: 0.05)
    static let warning = Color(red: 0.98, green: 0.70, blue: 0.10)
    static let serious = Color(red: 0.93, green: 0.51, blue: 0.35)
    static let critical = Color(red: 0.82, green: 0.23, blue: 0.23)
    static let grid = Color.primary.opacity(0.09)
    static let surface = Color(nsColor: .windowBackgroundColor)
    static let card = Color.primary.opacity(0.05)
}

extension HeatLevel {
    var color: Color {
        switch self {
        case .normal: return Theme.good
        case .warm: return Theme.warning
        case .hot: return Theme.serious
        case .critical: return Theme.critical
        }
    }

    var symbol: String {
        switch self {
        case .normal: return "checkmark.circle.fill"
        case .warm: return "thermometer.medium"
        case .hot: return "flame.fill"
        case .critical: return "exclamationmark.triangle.fill"
        }
    }
}

enum TimeRange: String, CaseIterable, Identifiable {
    case tenMinutes = "10 min", hour = "1 h", day = "24 h"
    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .tenMinutes: return 600
        case .hour: return 3600
        case .day: return 86400
        }
    }
}

struct DashboardContent: View {
    let snapshot: Snapshot
    let history: History
    let isSupported: Bool
    @State var range: TimeRange = .hour
    @State private var hoverDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            hero
            if !isSupported { unsupported }
            findings
            charts
            processes
            sensors
        }
        .padding(16)
        .frame(width: 400, alignment: .leading)
    }

    // MARK: Headline

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(snapshot.cpuCelsius.map { String(format: "%.0f", $0) } ?? "–")
                    .font(.system(size: 54, weight: .semibold, design: .rounded).monospacedDigit())
                Text("°C CPU")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Spacer()
                if let cpu = snapshot.cpuCelsius { levelBadge(HeatLevel(celsius: cpu)) }
            }
            HStack(spacing: 8) {
                tile("Ventoinhas", snapshot.fanEffort.map { String(format: "%.0f%%", $0) }, fanCaption)
                tile("Consumo CPU+GPU", snapshot.power.package.map { String(format: "%.0f W", $0) },
                     snapshot.power.system.map { String(format: "Mac: %.0f W", $0) })
                tile("Uso do CPU", snapshot.cpuUsage.map { String(format: "%.0f%%", $0) },
                     snapshot.speedLimit.map { "Velocidade: \($0)%" })
            }
        }
    }

    private var fanCaption: String? {
        guard !snapshot.fans.isEmpty else { return nil }
        let rpm = snapshot.fans.map(\.rpm).reduce(0, +) / Double(snapshot.fans.count)
        return String(format: "%.0f rpm", rpm)
    }

    private func levelBadge(_ level: HeatLevel) -> some View {
        HStack(spacing: 5) {
            Image(systemName: level.symbol).foregroundStyle(level.color)
            Text(level.label).font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(level.color.opacity(0.16)))
    }

    private func tile(_ title: String, _ value: String?, _ caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            Text(value ?? "–").font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
            Text(caption ?? " ").font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
    }

    private var unsupported: some View {
        Text("Não foi possível abrir o SMC. Esta app só funciona em Macs com processador Intel.")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }

    // MARK: Causes

    private var findings: some View {
        let items = Diagnosis.evaluate(snapshot)
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Porque está quente")
            if items.isEmpty {
                Label("Nada de anormal neste momento.", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12))
            }
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: symbol(item.severity))
                        .foregroundStyle(color(item.severity))
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).font(.system(size: 12, weight: .medium))
                        Text(item.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func symbol(_ severity: Finding.Severity) -> String {
        switch severity {
        case .serious: return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func color(_ severity: Finding.Severity) -> Color {
        switch severity {
        case .serious: return Theme.serious
        case .warning: return Theme.warning
        case .info: return .secondary
        }
    }

    // MARK: Timeline

    private var charts: some View {
        let now = Date()
        let start = now.addingTimeInterval(-range.seconds)
        let points = history.points(lastSeconds: range.seconds, now: now)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("Histórico")
                Spacer()
                HStack(spacing: 2) {
                    ForEach(TimeRange.allCases) { option in
                        Button { range = option } label: {
                            Text(option.rawValue)
                                .font(.system(size: 11, weight: range == option ? .semibold : .regular))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(range == option ? Theme.card : .clear))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text(readout(points))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
            chartTitle("Temperatura do CPU (°C) · tracejado: 95 °C")
            LineChart(points: points, value: { $0.cpu }, start: start, end: now,
                      domain: 30...100, ticks: [40, 70, 100], referenceLine: 95, hoverDate: $hoverDate)
                .frame(height: 96)
            chartTitle("Esforço das ventoinhas (%)")
            LineChart(points: points, value: { $0.fanEffort }, start: start, end: now,
                      domain: 0...100, ticks: [0, 50, 100], hoverDate: $hoverDate)
                .frame(height: 52)
            chartTitle("Consumo do CPU e GPU (W)")
            LineChart(points: points, value: { $0.packageWatts }, start: start, end: now,
                      domain: 0...50, ticks: [0, 25, 50], hoverDate: $hoverDate)
                .frame(height: 52)
            HStack {
                Text(axisLabel(start))
                Spacer()
                Text("agora")
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.leading, 30)
        }
    }

    private func axisLabel(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func readout(_ points: [HistoryPoint]) -> String {
        if points.isEmpty { return "A recolher dados…" }
        guard let hoverDate, let point = points.nearest(to: hoverDate) else {
            let average = points.map(\.cpu).reduce(0, +) / Double(points.count)
            let peak = points.map(\.cpu).max() ?? 0
            return String(format: "Média %.0f °C · máximo %.0f °C neste período", average, peak)
        }
        var parts = [axisLabel(point.date), String(format: "%.0f °C", point.cpu)]
        if let fan = point.fanEffort { parts.append(String(format: "ventoinhas %.0f%%", fan)) }
        if let watts = point.packageWatts { parts.append(String(format: "%.0f W", watts)) }
        return parts.joined(separator: " · ")
    }

    private func chartTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .medium)).padding(.top, 2)
    }

    // MARK: Details

    private var processes: some View {
        let top = Array(snapshot.processes.prefix(6))
        let scale = max(100, top.first?.cpu ?? 100)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("O que está a usar o CPU")
                Spacer()
                Text("100% = 1 thread de \(snapshot.coreCount)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            if top.isEmpty {
                Text("A medir…").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(top) { process in
                HStack(spacing: 8) {
                    Text(process.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .frame(width: 120, alignment: .leading)
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.series)
                            .frame(width: max(2, proxy.size.width * CGFloat(process.cpu / scale)), height: 6)
                            .frame(maxHeight: .infinity)
                    }
                    Text(String(format: "%.0f%%", process.cpu))
                        .font(.system(size: 12).monospacedDigit())
                        .frame(width: 42, alignment: .trailing)
                }
                .frame(height: 16)
            }
        }
    }

    private var sensors: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Sensores")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible())], spacing: 4) {
                ForEach(snapshot.sensors) { sensor in
                    HStack {
                        Text(sensor.name).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Text(String(format: "%.0f °C", sensor.celsius)).font(.system(size: 11).monospacedDigit())
                    }
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 13, weight: .semibold))
    }
}

struct DashboardPanel: View {
    @ObservedObject var monitor: Monitor

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                DashboardContent(snapshot: monitor.snapshot, history: monitor.history, isSupported: monitor.isSupported)
            }
            .frame(height: min(760, (NSScreen.main?.visibleFrame.height ?? 800) - 80))
            Divider()
            HStack {
                Button("Abrir registo") {
                    NSWorkspace.shared.activateFileViewerSelecting([History.defaultFileURL()])
                }
                Spacer()
                Button("Sair") {
                    monitor.saveHistory()
                    NSApp.terminate(nil)
                }
            }
            .buttonStyle(.link)
            .font(.system(size: 12))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .onAppear { monitor.setPanelVisible(true) }
        .onDisappear { monitor.setPanelVisible(false) }
    }
}
