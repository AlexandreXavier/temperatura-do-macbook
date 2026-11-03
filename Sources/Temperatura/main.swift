import AppKit
import SwiftUI
import ThermalCore

struct TemperaturaApp: App {
    @StateObject private var monitor: Monitor

    init() {
        let monitor = Monitor()
        monitor.start()
        _monitor = StateObject(wrappedValue: monitor)
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in monitor.saveHistory() }
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardPanel(monitor: monitor)
        } label: {
            MenuBarLabel(snapshot: monitor.snapshot)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let snapshot: Snapshot

    var body: some View {
        if let cpu = snapshot.cpuCelsius {
            Label(String(format: "%.0f°", cpu), systemImage: Self.symbol(HeatLevel(celsius: cpu)))
                .labelStyle(.titleAndIcon)
        } else {
            Label("–", systemImage: "thermometer.medium").labelStyle(.titleAndIcon)
        }
    }

    /// The menu bar is monochrome, so the level is told by the icon shape.
    static func symbol(_ level: HeatLevel) -> String {
        switch level {
        case .normal: return "thermometer.low"
        case .warm: return "thermometer.medium"
        case .hot: return "thermometer.high"
        case .critical: return "exclamationmark.triangle.fill"
        }
    }
}

/// One reading on stdout, for scripts and for checking the sensors without the UI.
func printSample() {
    let sampler = Sampler()
    _ = sampler.sample()
    Thread.sleep(forTimeInterval: 1)
    var snapshot = sampler.sample()
    snapshot.processes = Sampler.readTopProcesses()
    snapshot.battery = Sampler.readBattery()

    print("CPU: \(snapshot.cpuCelsius.map { String(format: "%.1f °C", $0) } ?? "–")")
    for sensor in snapshot.sensors {
        print(String(format: "  %@ %@: %.1f °C", sensor.key, sensor.name, sensor.celsius))
    }
    for fan in snapshot.fans {
        print(String(format: "Ventoinha %d: %.0f rpm (%.0f–%.0f), esforço %.0f%%", fan.index, fan.rpm, fan.minRPM, fan.maxRPM, fan.effort))
    }
    let p = snapshot.power
    print(String(format: "Consumo: pacote %.1f W, núcleos %.1f W, GPU %.1f W, Mac %.1f W",
                 p.package ?? .nan, p.cores ?? .nan, p.graphics ?? .nan, p.system ?? .nan))
    print(String(format: "Uso CPU: %.0f%%  Velocidade: %d%%  Swap: %.1f GB",
                 snapshot.cpuUsage ?? .nan, snapshot.speedLimit ?? -1, snapshot.swapUsedGB ?? .nan))
    for process in snapshot.processes.prefix(8) {
        print(String(format: "  %6.1f%%  %@", process.cpu, process.name))
    }
    for finding in Diagnosis.evaluate(snapshot) {
        print("[\(finding.id)] \(finding.title): \(finding.detail)")
    }
}

/// Renders the real dashboard with live data to a PNG, so the UI can be checked without opening it.
@MainActor
func renderSnapshot(to path: String, dark: Bool) {
    let sampler = Sampler()
    _ = sampler.sample()
    Thread.sleep(forTimeInterval: 1)
    var snapshot = sampler.sample()
    snapshot.processes = Sampler.readTopProcesses()
    snapshot.battery = Sampler.readBattery()

    let content = DashboardContent(
        snapshot: snapshot, history: History(fileURL: History.defaultFileURL()), isSupported: sampler.isSupported,
        range: .hour
    )
    .background(dark ? Color(white: 0.11) : Color(white: 0.98))
    .environment(\.colorScheme, dark ? .dark : .light)

    let renderer = ImageRenderer(content: content)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]),
          (try? png.write(to: URL(fileURLWithPath: path))) != nil else {
        FileHandle.standardError.write(Data("Falha ao gerar a imagem\n".utf8))
        exit(1)
    }
}

let arguments = CommandLine.arguments
if arguments.contains("--sample") {
    printSample()
} else if let index = arguments.firstIndex(of: "--snapshot"), arguments.count > index + 1 {
    MainActor.assumeIsolated {
        renderSnapshot(to: arguments[index + 1], dark: !arguments.contains("--light"))
    }
} else {
    TemperaturaApp.main()
}
