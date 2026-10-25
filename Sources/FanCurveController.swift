import Foundation

final class FanCurveController {
    private let service = FanControlService()
    private let controlDirectory = "/tmp/fanmacos-curve"
    private var process: Process?
    private var heartbeatTimer: Timer?
    private var isStopping = false

    private(set) var isRunning = false
    var onExit: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    private var targetPath: String { controlDirectory + "/target" }
    private var heartbeatPath: String { controlDirectory + "/heartbeat" }
    private var stopPath: String { controlDirectory + "/stop" }

    func start() throws {
        guard service.isReady else { throw FanError.helperMissing }

        let manager = FileManager.default
        try manager.createDirectory(
            atPath: controlDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        stopExisting()
        try? manager.removeItem(atPath: stopPath)
        writeHeartbeat()
        writeTarget(0)

        let logPath = controlDirectory + "/watch.log"
        if !manager.fileExists(atPath: logPath) {
            manager.createFile(atPath: logPath, contents: nil)
        }
        let log = FileHandle(forWritingAtPath: logPath)
        log?.seekToEndOfFile()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", FanControlBuild.helperPath, "watch", controlDirectory]
        process.standardOutput = log
        process.standardError = log
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRunning = false
                self.heartbeatTimer?.invalidate()
                self.heartbeatTimer = nil
                if !self.isStopping {
                    self.onExit?("O processo de vigilância terminou (código \(process.terminationStatus)).")
                }
            }
        }

        try process.run()
        self.process = process
        isStopping = false
        isRunning = true
        startHeartbeat()
    }

    func update(target: Double) {
        guard isRunning else { return }
        writeTarget(target)
        writeHeartbeat()
    }

    func stop() {
        guard isRunning || process != nil else { return }
        isStopping = true
        writeStop()
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        isRunning = false
        try? service.setAutoAll()
    }

    private func stopExisting() {
        writeStop()
        Thread.sleep(forTimeInterval: 1.3)
        try? FileManager.default.removeItem(atPath: stopPath)
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        writeHeartbeat()
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            self?.writeHeartbeat()
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    private func writeTarget(_ value: Double) {
        write(String(format: "%.0f", value), to: targetPath)
    }

    private func writeHeartbeat() {
        write(String(Date().timeIntervalSince1970), to: heartbeatPath)
    }

    private func writeStop() {
        write("stop", to: stopPath)
    }

    private func write(_ value: String, to path: String) {
        try? value.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
