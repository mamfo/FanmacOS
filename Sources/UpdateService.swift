import Foundation
import CryptoKit

struct UpdateInfo {
    let version: String
    let tag: String
    let zipURL: URL
    let checksumURL: URL?
    let releaseURL: URL
    let notes: String?
}

enum UpdateError: LocalizedError {
    case invalidResponse
    case server(Int)
    case missingAsset
    case downloadFailed
    case checksumMismatch
    case invalidPackage(String)
    case signatureInvalid
    case notInstalledInApplications
    case notWritable(String)
    case installationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Resposta inválida do GitHub."
        case .server(let code):
            return "O GitHub devolveu o erro \(code)."
        case .missingAsset:
            return "A versão publicada não tem o ficheiro ZIP da app."
        case .downloadFailed:
            return "Não foi possível descarregar a atualização."
        case .checksumMismatch:
            return "O ficheiro descarregado não corresponde à soma de verificação publicada."
        case .invalidPackage(let message):
            return "Pacote de atualização inválido: \(message)"
        case .signatureInvalid:
            return "A assinatura da nova versão não é válida."
        case .notInstalledInApplications:
            return "A app tem de estar na pasta Aplicações para se atualizar automaticamente."
        case .notWritable(let path):
            return "Sem permissão para escrever em \(path)."
        case .installationFailed(let message):
            return "Falha ao instalar a atualização: \(message)"
        }
    }
}

final class UpdateService {
    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: URL
        let body: String?
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case body
            case assets
        }
    }

    private struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    private struct ProcessResult {
        let status: Int32
        let output: String
    }

    let repo: String
    let currentVersion: String
    private let session: URLSession

    init(repo: String = AppInfo.githubSlug, currentVersion: String = AppInfo.version) {
        self.repo = repo
        self.currentVersion = currentVersion

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 60
        configuration.httpAdditionalHeaders = ["User-Agent": "FanmacOS/\(currentVersion)"]
        session = URLSession(configuration: configuration)
    }

    var isRunningFromApplications: Bool {
        let path = Bundle.main.bundleURL.standardizedFileURL.path
        let homeApplications = "/Users/\(NSUserName())/Applications/"
        return path.hasPrefix("/Applications/") || path.hasPrefix(homeApplications)
    }

    func check() async throws -> UpdateInfo? {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("FanmacOS/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.invalidResponse }
        if http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else { throw UpdateError.server(http.statusCode) }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let version = Self.normalizedVersion(release.tagName)
        guard Self.isNewer(version, than: currentVersion) else { return nil }

        guard let zip = release.assets.first(where: {
            $0.name.lowercased().hasPrefix("fanmacos-") && $0.name.lowercased().hasSuffix(".zip")
        }) else {
            throw UpdateError.missingAsset
        }

        let checksum = release.assets.first(where: { $0.name.lowercased().hasSuffix(".sha256") })

        return UpdateInfo(
            version: version,
            tag: release.tagName,
            zipURL: zip.browserDownloadURL,
            checksumURL: checksum?.browserDownloadURL,
            releaseURL: release.htmlURL,
            notes: release.body
        )
    }

    func prepare(_ update: UpdateInfo) async throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FanmacOSUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let (downloadURL, response) = try await session.download(from: update.zipURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw UpdateError.downloadFailed
            }

            let zipURL = directory.appendingPathComponent("update.zip")
            try FileManager.default.moveItem(at: downloadURL, to: zipURL)

            let actualHash = Self.sha256(of: zipURL)
            if let checksumURL = update.checksumURL {
                let (data, _) = try await session.data(from: checksumURL)
                let checksumText = String(data: data, encoding: .utf8) ?? ""
                guard let expected = Self.checksum(in: checksumText, for: zipURL.lastPathComponent),
                      expected.caseInsensitiveCompare(actualHash) == .orderedSame else {
                    throw UpdateError.checksumMismatch
                }
            }

            let extractURL = directory.appendingPathComponent("extract", isDirectory: true)
            try FileManager.default.createDirectory(at: extractURL, withIntermediateDirectories: true)
            let extract = run("/usr/bin/ditto", ["-x", "-k", zipURL.path, extractURL.path])
            guard extract.status == 0 else {
                throw UpdateError.invalidPackage(extract.output)
            }

            let appURL = extractURL.appendingPathComponent("FanmacOS.app", isDirectory: true)
            let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
            guard let plist = NSDictionary(contentsOf: plistURL),
                  let version = plist["CFBundleShortVersionString"] as? String else {
                throw UpdateError.invalidPackage("Info.plist ausente ou inválido.")
            }
            guard Self.normalizedVersion(version) == update.version else {
                throw UpdateError.invalidPackage("a versão do pacote não corresponde à publicada.")
            }

            let signature = run("/usr/bin/codesign", ["--verify", "--deep", "--strict", appURL.path])
            guard signature.status == 0 else {
                throw UpdateError.signatureInvalid
            }

            return appURL
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func install(stagedApp: URL) throws {
        let target = Bundle.main.bundleURL.standardizedFileURL
        let targetPath = target.path
        let homeApplications = "/Users/\(NSUserName())/Applications/"

        guard targetPath.hasPrefix("/Applications/") || targetPath.hasPrefix(homeApplications) else {
            throw UpdateError.notInstalledInApplications
        }

        let parent = target.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw UpdateError.notWritable(parent.path)
        }

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fanmacos-update-\(UUID().uuidString).sh")
        let newAppPath = targetPath + ".new"
        let oldAppPath = targetPath + ".old"

        let script = """
        #!/bin/sh
        set -e
        PID=\(ProcessInfo.processInfo.processIdentifier)
        while /bin/kill -0 "$PID" 2>/dev/null; do
            /bin/sleep 0.2
        done
        /bin/rm -rf \(shellQuote(newAppPath))
        /usr/bin/ditto \(shellQuote(stagedApp.path)) \(shellQuote(newAppPath))
        /bin/rm -rf \(shellQuote(oldAppPath))
        /bin/mv \(shellQuote(targetPath)) \(shellQuote(oldAppPath))
        /bin/mv \(shellQuote(newAppPath)) \(shellQuote(targetPath))
        /usr/bin/xattr -dr com.apple.quarantine \(shellQuote(targetPath)) 2>/dev/null || true
        /usr/bin/open \(shellQuote(targetPath))
        /bin/rm -rf \(shellQuote(oldAppPath))
        /bin/rm -f "$0"
        """

        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [scriptURL.path]
            try process.run()
        } catch {
            throw UpdateError.installationFailed(error.localizedDescription)
        }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let candidateParts = versionComponents(candidate)
        let currentParts = versionComponents(current)
        let count = max(candidateParts.count, currentParts.count)

        for index in 0..<count {
            let candidatePart = index < candidateParts.count ? candidateParts[index] : 0
            let currentPart = index < currentParts.count ? currentParts[index] : 0
            if candidatePart != currentPart {
                return candidatePart > currentPart
            }
        }
        return false
    }

    static func normalizedVersion(_ value: String) -> String {
        var version = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if version.lowercased().hasPrefix("v") {
            version.removeFirst()
        }
        return version
    }

    private static func versionComponents(_ value: String) -> [Int] {
        normalizedVersion(value)
            .split(separator: ".")
            .map { component in
                Int(component.prefix { $0.isNumber }) ?? 0
            }
    }

    private static func sha256(of url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func checksum(in text: String, for filename: String) -> String? {
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2 else { continue }
            if parts.last.map(String.init) == filename {
                return String(parts[0])
            }
        }
        return nil
    }

    private func run(_ executable: String, _ arguments: [String]) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return ProcessResult(status: -1, output: error.localizedDescription)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ProcessResult(
            status: process.terminationStatus,
            output: String(data: data, encoding: .utf8) ?? ""
        )
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
