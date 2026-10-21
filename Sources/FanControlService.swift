import AppKit
import Foundation

final class FanControlService {
    struct ProcessResult {
        let status: Int32
        let output: String
    }

    var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: FanControlBuild.helperPath)
            && FileManager.default.fileExists(atPath: FanControlBuild.sudoersPath)
    }

    var installedVersion: String? {
        guard isInstalled else { return nil }
        let result = runProcess(FanControlBuild.helperPath, ["version"])
        guard result.status == 0 else { return nil }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isReady: Bool {
        isInstalled && installedVersion == FanControlBuild.helperVersion
    }

    func install() throws {
        let helperSource = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/fanctl")
            .path
        guard FileManager.default.isExecutableFile(atPath: helperSource) else {
            throw FanError.installFailed("o binário fanctl não foi encontrado dentro da app.")
        }

        let user = NSUserName()
        guard user.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else {
            throw FanError.installFailed("nome de utilizador inválido.")
        }

        let script = installScript(helperSource: helperSource, user: user)
        let scriptURL = try makeTemporaryScript(script)
        defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }
        try runAsAdministrator(scriptURL)

        let check = runProcess("/usr/bin/sudo", ["-n", FanControlBuild.helperPath, "version"])
        guard check.status == 0 else {
            let detail = check.output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw FanError.installFailed(detail.isEmpty ? "a autorização não ficou ativa." : detail)
        }
    }

    func uninstall() throws {
        let script = uninstallScript()
        let scriptURL = try makeTemporaryScript(script)
        defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }
        try runAsAdministrator(scriptURL)
    }

    func setSpeed(fan: Int, rpm: Double) throws {
        try runHelper(["set", String(Int(rpm.rounded())), "--fan", String(fan)])
    }

    func setAuto(fan: Int) throws {
        try runHelper(["auto", "--fan", String(fan)])
    }

    func setAutoAll() throws {
        try runHelper(["auto"])
    }

    func setMaximumAll() throws {
        try runHelper(["max"])
    }

    func installScript(helperSource: String, user: String) -> String {
        return """
        #!/bin/sh
        set -eu
        HELPER_SRC=\(shellQuote(helperSource))
        HELPER_DIR=\(shellQuote(FanControlBuild.helperDirectory))
        HELPER_DST="$HELPER_DIR/fanctl"
        SUDOERS=\(shellQuote(FanControlBuild.sudoersPath))
        /usr/bin/install -d -m 755 -o root -g wheel "$HELPER_DIR"
        /usr/bin/install -m 755 -o root -g wheel "$HELPER_SRC" "$HELPER_DST"
        TMP="$(/usr/bin/mktemp /tmp/fanmacos-sudoers.XXXXXX)"
        trap '/bin/rm -f "$TMP"' EXIT
        /usr/bin/printf '%s\\n' '\(user) ALL=(root) NOPASSWD: \(FanControlBuild.helperPath)' > "$TMP"
        /usr/sbin/visudo -cf "$TMP" >/dev/null
        /usr/bin/install -m 440 -o root -g wheel "$TMP" "$SUDOERS"
        "$HELPER_DST" version >/dev/null
        """
    }

    func uninstallScript() -> String {
        return """
        #!/bin/sh
        set -eu
        if [ -x \(shellQuote(FanControlBuild.helperPath)) ]; then
            \(shellQuote(FanControlBuild.helperPath)) auto >/dev/null 2>&1 || true
        fi
        /bin/rm -f \(shellQuote(FanControlBuild.sudoersPath))
        /bin/rm -f \(shellQuote(FanControlBuild.helperPath))
        /bin/rmdir \(shellQuote(FanControlBuild.helperDirectory)) 2>/dev/null || true
        """
    }

    private func runHelper(_ arguments: [String]) throws {
        guard isInstalled else { throw FanError.helperMissing }
        let result = runProcess("/usr/bin/sudo", ["-n", FanControlBuild.helperPath] + arguments)
        guard result.status == 0 else {
            let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if output.localizedCaseInsensitiveContains("password is required")
                || output.localizedCaseInsensitiveContains("no tty present")
                || output.localizedCaseInsensitiveContains("a terminal is required") {
                throw FanError.helperMissing
            }
            throw FanError.helperFailed(output)
        }
    }

    private func runProcess(_ executable: String, _ arguments: [String]) -> ProcessResult {
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

    private func makeTemporaryScript(_ content: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FanmacOS-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let url = directory.appendingPathComponent("install.sh")
        try content.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    private func runAsAdministrator(_ scriptURL: URL) throws {
        let shellCommand = "/bin/sh \(shellQuote(scriptURL.path))"
        let source = "do shell script \(appleScriptLiteral(shellCommand)) with administrator privileges"
        guard let appleScript = NSAppleScript(source: source) else {
            throw FanError.installFailed("não foi possível preparar o pedido de autorização.")
        }

        var errorInfo: NSDictionary?
        appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let number = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "autorização cancelada."
            if number == -128 {
                throw FanError.authorizationCancelled
            }
            throw FanError.installFailed(message)
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptLiteral(_ value: String) -> String {
        var escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        escaped = escaped.replacingOccurrences(of: "\n", with: " ")
        return "\"\(escaped)\""
    }
}
