import Foundation

enum FanProfile: String, CaseIterable {
    case silent
    case balanced
    case performance

    var title: String {
        switch self {
        case .silent: return "Silencioso"
        case .balanced: return "Equilibrado"
        case .performance: return "Desempenho"
        }
    }

    var start: Double {
        switch self {
        case .silent: return 70
        case .balanced: return 55
        case .performance: return 45
        }
    }

    var full: Double {
        switch self {
        case .silent: return 100
        case .balanced: return 90
        case .performance: return 80
        }
    }

    static func matching(start: Double, full: Double) -> FanProfile? {
        allCases.first {
            abs($0.start - start) < 0.5 && abs($0.full - full) < 0.5
        }
    }
}
