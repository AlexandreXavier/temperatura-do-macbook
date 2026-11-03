import Foundation
import ThermalCore

/// Owns the sampling loop. Costly reads run far less often than the sensors,
/// so that the monitor adds as little heat as possible.
final class Monitor: ObservableObject {
    static let sensorInterval: TimeInterval = 5
    static let processIntervalHidden: TimeInterval = 120
    static let processIntervalVisible: TimeInterval = 20
    static let batteryInterval: TimeInterval = 600

    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var history: History

    let isSupported: Bool
    private let sampler = Sampler()
    private let queue = DispatchQueue(label: "temperatura.sampler", qos: .utility)
    private var timer: DispatchSourceTimer?

    // Only touched on `queue`.
    private var processes: [ProcessLoad] = []
    private var battery: BatteryHealth?
    private var lastProcessRead = Date.distantPast
    private var lastBatteryRead = Date.distantPast
    private var panelVisible = false

    init(history: History = History(fileURL: History.defaultFileURL())) {
        self.history = history
        isSupported = sampler.isSupported
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: Self.sensorInterval, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    func setPanelVisible(_ visible: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.panelVisible = visible
            if visible { self.lastProcessRead = .distantPast; self.tick() }
        }
    }

    func saveHistory() {
        history.flushBucket()
    }

    private func tick() {
        let now = Date()
        var snapshot = sampler.sample()

        if now.timeIntervalSince(lastBatteryRead) >= Self.batteryInterval {
            battery = Sampler.readBattery()
            lastBatteryRead = now
        }
        let interval = panelVisible ? Self.processIntervalVisible : Self.processIntervalHidden
        if now.timeIntervalSince(lastProcessRead) >= interval {
            processes = Sampler.readTopProcesses()
            lastProcessRead = now
        }
        snapshot.battery = battery
        snapshot.processes = processes

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var snapshot = snapshot
            if let cpu = snapshot.cpuCelsius {
                self.history.add(HistoryPoint(
                    date: snapshot.date, cpu: cpu,
                    fanEffort: snapshot.fanEffort, packageWatts: snapshot.power.package
                ))
            }
            snapshot.sustained = SustainedLoad(recent: self.history.fine, now: snapshot.date)
            self.snapshot = snapshot
        }
    }
}
