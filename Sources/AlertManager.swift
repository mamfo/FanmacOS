import Foundation
import UserNotifications

final class AlertManager: NSObject, UNUserNotificationCenterDelegate {
    private let prefs = Preferences.shared
    private let center = UNUserNotificationCenter.current()

    private var isAboveTemperature = false
    private var lastTemperatureNotification = Date.distantPast
    private var batteryLowActive = false
    private var lastBatteryNotification = Date.distantPast
    private var fanStallSamples = 0
    private var lastFanNotification = Date.distantPast
    private var highLoadSince: Date?
    private var lastLoadNotification = Date.distantPast
    private var lastDiskNotification = Date.distantPast

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                completion?(granted)
            }
        }
    }

    func sendTestNotification() {
        requestAuthorization { _ in
            self.send(
                title: "FanmacOS",
                body: "As notificações estão a funcionar.",
                ignorePreferences: true
            )
        }
    }

    func evaluate(
        snapshot: TemperatureSnapshot,
        energy: EnergySnapshot,
        fans: [FanInfo],
        diskFreeBytes: Int64?,
        diskTotalBytes: Int64?
    ) {
        guard prefs.alertsEnabled else {
            isAboveTemperature = false
            batteryLowActive = false
            fanStallSamples = 0
            highLoadSince = nil
            return
        }

        evaluateTemperature(snapshot)
        guard prefs.systemAlertsEnabled else { return }

        evaluateBattery(energy.battery)
        evaluateFans(fans)
        evaluateLoad(energy)
        evaluateDisk(free: diskFreeBytes, total: diskTotalBytes)
    }

    private func evaluateTemperature(_ snapshot: TemperatureSnapshot) {
        guard let temperature = snapshot.systemMax ?? snapshot.cpuMax else {
            isAboveTemperature = false
            return
        }

        let threshold = prefs.alertThreshold
        if temperature >= threshold {
            guard !isAboveTemperature else { return }
            isAboveTemperature = true
            guard Date().timeIntervalSince(lastTemperatureNotification) > 600 else { return }
            lastTemperatureNotification = Date()
            send(
                title: "Temperatura elevada",
                body: String(format: "O hardware atingiu %.0f °C (limite %.0f °C).", temperature, threshold)
            )
        } else if temperature <= threshold - 5 {
            isAboveTemperature = false
        }
    }

    private func evaluateBattery(_ battery: BatteryInfo?) {
        guard let battery else {
            batteryLowActive = false
            return
        }

        if !battery.charging, battery.percentage <= 20 {
            guard !batteryLowActive else { return }
            batteryLowActive = true
            guard Date().timeIntervalSince(lastBatteryNotification) > 3600 else { return }
            lastBatteryNotification = Date()
            send(
                title: "Bateria baixa",
                body: "A bateria está em \(battery.percentage)%. Liga o carregador."
            )
        } else if battery.charging || battery.percentage > 25 {
            batteryLowActive = false
        }
    }

    private func evaluateFans(_ fans: [FanInfo]) {
        let stalled = fans.first {
            $0.manual && $0.targetRPM > 0 && $0.actualRPM < $0.targetRPM * 0.4
        }

        if let fan = stalled {
            fanStallSamples += 1
            if fanStallSamples >= 3, Date().timeIntervalSince(lastFanNotification) > 1800 {
                lastFanNotification = Date()
                send(
                    title: "Ventoinha sem responder",
                    body: String(
                        format: "A ventoinha %d devia estar a %.0f rpm mas está a %.0f rpm.",
                        fan.index + 1,
                        fan.targetRPM,
                        fan.actualRPM
                    )
                )
            }
        } else {
            fanStallSamples = 0
        }
    }

    private func evaluateLoad(_ energy: EnergySnapshot) {
        let cpu = energy.cpuLoad ?? 0
        let ram = energy.memoryUsage ?? 0
        let load = max(cpu, ram)

        if load >= 90 {
            if highLoadSince == nil {
                highLoadSince = Date()
            }
            if let since = highLoadSince,
               Date().timeIntervalSince(since) >= 300,
               Date().timeIntervalSince(lastLoadNotification) > 1800 {
                lastLoadNotification = Date()
                send(
                    title: "Carga elevada",
                    body: String(
                        format: "CPU %.0f%% · RAM %.0f%% há mais de 5 minutos.",
                        cpu,
                        ram
                    )
                )
            }
        } else if load < 85 {
            highLoadSince = nil
        }
    }

    private func evaluateDisk(free: Int64?, total: Int64?) {
        guard let free, let total, total > 0 else { return }
        let ratio = Double(free) / Double(total)
        guard free < 5_000_000_000 || ratio < 0.05 else { return }
        guard Date().timeIntervalSince(lastDiskNotification) > 86400 else { return }

        lastDiskNotification = Date()
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        send(
            title: "Pouco espaço livre",
            body: "O disco do sistema tem \(formatter.string(fromByteCount: free)) livres."
        )
    }

    private func send(title: String, body: String, ignorePreferences: Bool = false) {
        if !ignorePreferences {
            guard prefs.alertsEnabled else { return }
            guard !suppressedByQuietHours() else { return }
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "fanmacos.alert.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    private func suppressedByQuietHours() -> Bool {
        guard prefs.quietHoursEnabled else { return false }
        let hour = Calendar.current.component(.hour, from: Date())
        return Self.isQuiet(hour: hour, start: 23, end: 8)
    }

    static func isQuiet(hour: Int, start: Int, end: Int) -> Bool {
        if start <= end {
            return hour >= start && hour < end
        }
        return hour >= start || hour < end
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
