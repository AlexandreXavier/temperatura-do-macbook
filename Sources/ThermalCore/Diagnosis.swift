import Foundation

public struct Finding: Identifiable, Equatable, Sendable {
    public enum Severity: Int, Sendable { case info, warning, serious }

    public let id: String
    public let severity: Severity
    public let title: String
    public let detail: String

    public init(id: String, severity: Severity, title: String, detail: String) {
        self.id = id
        self.severity = severity
        self.title = title
        self.detail = detail
    }
}

/// Turns one reading into plain-language causes. Rules only state what the sensors show;
/// anything they cannot prove (dust, dried paste) is worded as a suspicion.
public enum Diagnosis {
    /// Sustained package power (about half of a 47 W TDP) under which a healthy cooler
    /// should keep this CPU well below `lowPowerHotCelsius`.
    static let lowPowerWatts = 25.0
    static let lowPowerHotCelsius = 75.0
    static let graphicsWatts = 8.0
    static let kernelTaskPercent = 30.0
    static let swapGB = 2.0
    static let batteryCapacityPercent = 80.0
    static let appPercent = 25.0

    public static func evaluate(_ s: Snapshot) -> [Finding] {
        var findings: [Finding] = []

        if let limit = s.speedLimit, limit < 100 {
            findings.append(Finding(
                id: "throttle", severity: .serious,
                title: "CPU limitado a \(limit)% da velocidade",
                detail: "O macOS está a reduzir a velocidade para baixar a temperatura."
            ))
        }

        if let sustained = s.sustained, sustained.watts < lowPowerWatts, sustained.cpu >= lowPowerHotCelsius {
            let fans = sustained.fanEffort.map { String(format: " com ventoinhas a %.0f%%", $0) } ?? ""
            findings.append(Finding(
                id: "cooling", severity: .serious,
                title: "Muito quente para o pouco que consome",
                detail: String(format: "Média de 3 min: %.0f °C a %.0f W%@. Pode ser arrefecimento fraco: pó ou pasta térmica gasta.", sustained.cpu, sustained.watts, fans)
            ))
        }

        if let kernel = s.processes.first(where: { $0.name == "kernel_task" }), kernel.cpu >= kernelTaskPercent {
            findings.append(Finding(
                id: "kernel", severity: .warning,
                title: String(format: "kernel_task a %.0f%% de CPU", kernel.cpu),
                detail: "É um sintoma: costuma ser o macOS a ocupar o CPU para o arrefecer, ou drivers e E/S do sistema."
            ))
        }

        if let graphics = s.power.graphics, graphics >= graphicsWatts {
            findings.append(Finding(
                id: "graphics", severity: .warning,
                title: String(format: "Gráficos a consumir %.0f W", graphics),
                detail: "A GPU integrada partilha o dissipador com o CPU. Vídeo, separadores e o ecrã Retina pesam aqui."
            ))
        }

        let apps = s.processes.filter { $0.name != "kernel_task" && $0.cpu >= appPercent }
        if let top = apps.first {
            findings.append(Finding(
                id: "app", severity: .warning,
                title: String(format: "%@ a %.0f%% de CPU", top.name, top.cpu),
                detail: "É a aplicação que mais calor gera neste momento."
            ))
        }

        if let swap = s.swapUsedGB, swap >= swapGB {
            findings.append(Finding(
                id: "swap", severity: .info,
                title: String(format: "%.1f GB de memória em swap", swap),
                detail: "A memória não chega para o que está aberto, e o disco é usado em substituição."
            ))
        }

        if let battery = s.battery, battery.capacityPercent < batteryCapacityPercent {
            findings.append(Finding(
                id: "battery", severity: .warning,
                title: String(format: "Bateria com %.0f%% da capacidade original", battery.capacityPercent),
                detail: "\(battery.cycles) ciclos. Não é a causa do calor, mas deve ser substituída. Verifica se está inchada."
            ))
        }

        return findings.sorted { $0.severity.rawValue > $1.severity.rawValue }
    }
}
