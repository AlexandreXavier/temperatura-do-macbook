import SwiftUI
import ThermalCore

/// Single-series line over time. Charts stacked on the same window share the hover position,
/// so every measure can be read at one instant without a second y-axis.
struct LineChart: View {
    let points: [HistoryPoint]
    let value: (HistoryPoint) -> Double?
    let start: Date
    let end: Date
    let domain: ClosedRange<Double>
    let ticks: [Double]
    var referenceLine: Double?
    @Binding var hoverDate: Date?

    private let axisWidth: CGFloat = 30

    var body: some View {
        GeometryReader { proxy in
            let plot = CGRect(x: axisWidth, y: 4, width: proxy.size.width - axisWidth, height: proxy.size.height - 8)
            ZStack(alignment: .topLeading) {
                ForEach(ticks, id: \.self) { tick in
                    Path { path in
                        let y = yPosition(tick, in: plot)
                        path.move(to: CGPoint(x: plot.minX, y: y))
                        path.addLine(to: CGPoint(x: plot.maxX, y: y))
                    }
                    .stroke(Theme.grid, lineWidth: 1)
                    Text("\(Int(tick))")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: axisWidth - 6, alignment: .trailing)
                        .position(x: (axisWidth - 6) / 2, y: yPosition(tick, in: plot))
                }
                if let referenceLine {
                    Path { path in
                        let y = yPosition(referenceLine, in: plot)
                        path.move(to: CGPoint(x: plot.minX, y: y))
                        path.addLine(to: CGPoint(x: plot.maxX, y: y))
                    }
                    .stroke(Theme.critical, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                linePath(in: plot)
                    .stroke(Theme.series, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if let hover = hoverDate {
                    crosshair(at: hover, in: plot)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let fraction = max(0, min(1, (location.x - plot.minX) / plot.width))
                    hoverDate = start.addingTimeInterval(end.timeIntervalSince(start) * fraction)
                case .ended:
                    hoverDate = nil
                }
            }
        }
    }

    private func xPosition(_ date: Date, in plot: CGRect) -> CGFloat {
        let span = end.timeIntervalSince(start)
        return plot.minX + plot.width * CGFloat(date.timeIntervalSince(start) / span)
    }

    private func yPosition(_ number: Double, in plot: CGRect) -> CGFloat {
        let clamped = min(domain.upperBound, max(domain.lowerBound, number))
        let fraction = (clamped - domain.lowerBound) / (domain.upperBound - domain.lowerBound)
        return plot.maxY - plot.height * CGFloat(fraction)
    }

    /// Breaks the line across gaps (the Mac was asleep or the app closed) instead of bridging them.
    private func linePath(in plot: CGRect) -> Path {
        let gap = max(30, end.timeIntervalSince(start) / 40)
        var path = Path()
        var previous: Date?
        for point in points {
            guard let number = value(point) else { previous = nil; continue }
            let location = CGPoint(x: xPosition(point.date, in: plot), y: yPosition(number, in: plot))
            if let previous, point.date.timeIntervalSince(previous) <= gap {
                path.addLine(to: location)
            } else {
                path.move(to: location)
            }
            previous = point.date
        }
        return path
    }

    @ViewBuilder
    private func crosshair(at date: Date, in plot: CGRect) -> some View {
        let x = xPosition(date, in: plot)
        Path { path in
            path.move(to: CGPoint(x: x, y: plot.minY))
            path.addLine(to: CGPoint(x: x, y: plot.maxY))
        }
        .stroke(Color.secondary, lineWidth: 1)
        if let nearest = points.nearest(to: date), let number = value(nearest) {
            Circle()
                .fill(Theme.series)
                .overlay(Circle().stroke(Theme.surface, lineWidth: 2))
                .frame(width: 10, height: 10)
                .position(x: xPosition(nearest.date, in: plot), y: yPosition(number, in: plot))
        }
    }
}

extension Array where Element == HistoryPoint {
    func nearest(to date: Date) -> HistoryPoint? {
        self.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}
