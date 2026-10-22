import Foundation

enum AppInfo {
    static let developer = "mamfo.net"
    static let website = "https://mamfo.net"
    static let githubOwner = "mamfo"
    static let githubRepo = "FanmacOS"
    static let githubSlug = "mamfo/FanmacOS"
    static let releasesURL = URL(string: "https://github.com/mamfo/FanmacOS/releases")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.1"
    }

    static var footer: String {
        "FanmacOS \(version) · desenvolvido por \(developer)"
    }
}
