import Foundation

enum FanCurve {
    static func normalizedSettings(start: Double, full: Double) -> (start: Double, full: Double) {
        let clampedStart = min(95, max(20, start))
        let clampedFull = min(110, max(clampedStart + 1, full))
        return (clampedStart, clampedFull)
    }

    static func target(
        temperature: Double,
        start: Double,
        full: Double,
        minRPM: Double,
        maxRPM: Double
    ) -> Double {
        let settings = normalizedSettings(start: start, full: full)
        let range = max(1, settings.full - settings.start)
        let fraction = min(1, max(0, (temperature - settings.start) / range))
        let minimum = max(0, minRPM)
        let maximum = max(minimum, maxRPM)
        return minimum + (maximum - minimum) * fraction
    }
}
