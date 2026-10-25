import Foundation

struct HistorySample {
    let date: Date
    let cpuMax: Double?
    let systemMax: Double?
    let download: Double
    let upload: Double
    let diskRead: Double
    let diskWrite: Double
    let cpuLoad: Double?
}

final class MetricsHistory {
    private(set) var samples: [HistorySample] = []

    let retention: TimeInterval
    let maxSamples: Int

    init(retention: TimeInterval = 15 * 60, maxSamples: Int = 600) {
        self.retention = retention
        self.maxSamples = maxSamples
    }

    func append(_ sample: HistorySample) {
        samples.append(sample)
        trim()
    }

    func clear() {
        samples.removeAll()
    }

    private func trim() {
        let cutoff = Date().addingTimeInterval(-retention)
        while let first = samples.first, first.date < cutoff {
            samples.removeFirst()
        }
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
    }

    func csv() -> String {
        let formatter = ISO8601DateFormatter()
        var lines = [
            "timestamp,cpu_max_c,system_max_c,network_down_bps,network_up_bps,disk_read_bps,disk_write_bps,cpu_load_percent"
        ]

        for sample in samples {
            let fields: [String] = [
                formatter.string(from: sample.date),
                number(sample.cpuMax),
                number(sample.systemMax),
                String(format: "%.2f", sample.download),
                String(format: "%.2f", sample.upload),
                String(format: "%.2f", sample.diskRead),
                String(format: "%.2f", sample.diskWrite),
                number(sample.cpuLoad)
            ]
            lines.append(fields.joined(separator: ","))
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func number(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.2f", value)
    }
}
