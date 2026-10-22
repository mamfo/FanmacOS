import Foundation

enum StatusItemPositioning {
    static let temperatureName = "FanmacOSTemperature"

    static func apply() {
        UserDefaults.standard.removeObject(forKey: "NSStatusItem Preferred Position FanmacOSNetwork")
        UserDefaults.standard.removeObject(forKey: "NSStatusItem Preferred Position FanmacOSDisk")
        ensurePosition(for: temperatureName)
    }

    static func ensurePosition(for name: String) {
        let key = "NSStatusItem Preferred Position \(name)"
        if UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(0.0, forKey: key)
        }
    }
}
