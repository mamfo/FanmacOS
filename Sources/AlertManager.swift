import Foundation
import UserNotifications

final class AlertManager: NSObject, UNUserNotificationCenterDelegate {
    private let prefs = Preferences.shared
    private let center = UNUserNotificationCenter.current()
    private var isAboveThreshold = false
    private var lastNotification = Date.distantPast

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

    func evaluate(snapshot: TemperatureSnapshot) {
        guard prefs.alertsEnabled else {
            isAboveThreshold = false
            return
        }
        guard let temperature = snapshot.systemMax ?? snapshot.cpuMax else {
            isAboveThreshold = false
            return
        }

        let threshold = prefs.alertThreshold
        if temperature >= threshold {
            guard !isAboveThreshold else { return }
            isAboveThreshold = true
            guard Date().timeIntervalSince(lastNotification) > 600 else { return }
            lastNotification = Date()
            notify(temperature: temperature, threshold: threshold)
        } else if temperature <= threshold - 5 {
            isAboveThreshold = false
        }
    }

    private func notify(temperature: Double, threshold: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Temperatura elevada"
        content.body = String(
            format: "O hardware atingiu %.0f °C (limite %.0f °C).",
            temperature,
            threshold
        )
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "fanmacos.temperature.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
