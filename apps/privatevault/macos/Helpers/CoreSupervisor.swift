import Foundation
import Darwin

/// The parent owns the only write end of stdin. EOF means the app has exited,
/// including SIGKILL. Only this supervisor's retained child is ever signalled.
@main
struct CoreSupervisor {
    static func main() {
        umask(0o077)
        let args = CommandLine.arguments
        guard args.count == 5 else { exit(2) }
        let core = URL(fileURLWithPath: args[1]).standardizedFileURL
        let run = URL(fileURLWithPath: args[2]).standardizedFileURL
        let config = URL(fileURLWithPath: args[3]).standardizedFileURL
        let info = URL(fileURLWithPath: args[4]).standardizedFileURL
        guard config == run.appendingPathComponent("config.json"),
              info == run.appendingPathComponent("supervisor.json"),
              UUID(uuidString: run.lastPathComponent) != nil,
              FileManager.default.isExecutableFile(atPath: core.path) else { exit(2) }
        let worker = SupervisorWorker(core: core, run: run, config: config, info: info)
        worker.begin()
        withExtendedLifetime(worker) { dispatchMain() }
    }
}

private final class SupervisorWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.privatevault.w01.supervisor")
    private let process = Process()
    private let core: URL
    private let run: URL
    private let config: URL
    private let info: URL
    private var finished = false
    private var launched = false
    private var input: DispatchSourceRead?
    private var signals: [DispatchSourceSignal] = []

    init(core: URL, run: URL, config: URL, info: URL) {
        self.core = core; self.run = run; self.config = config; self.info = info
    }

    func begin() {
        queue.async {
            do { try self.start() }
            catch { self.stopAndFinish(reason: "initialization_failed", exitCode: 1) }
        }
    }

    private func start() throws {
        process.executableURL = core
        process.arguments = ["--data", run.path, "--config", config.path, "server"]
        process.currentDirectoryURL = run
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TMPDIR": run.appendingPathComponent("temp").path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        launched = true
        process.terminationHandler = { [weak self] child in
            guard let self else { return }
            self.queue.async { self.finish(reason: "core_exited", exitCode: child.terminationStatus) }
        }
        var identity = proc_bsdinfo()
        guard proc_pidinfo(process.processIdentifier, PROC_PIDTBSDINFO, 0, &identity,
                           Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size else {
            throw NSError(domain: "W01Supervisor", code: 1)
        }
        let stamp = "\(identity.pbi_start_tvsec).\(identity.pbi_start_tvusec)|\(core.resolvingSymlinksInPath().path)"
        try write(["schema": 1, "core_pid": Int(process.processIdentifier), "core_binary": core.path,
                   "started": stamp, "supervisor_pid": Int(getpid()), "instance": run.lastPathComponent], to: info)

        let source = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: queue)
        source.setEventHandler { [weak self] in
            var byte: UInt8 = 0
            let count = Darwin.read(STDIN_FILENO, &byte, 1)
            if count == 0 { self?.stopAndFinish(reason: "parent_pipe_closed", exitCode: 0) }
        }
        input = source
        source.resume()
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler { [weak self] in self?.stopAndFinish(reason: "supervisor_stopped", exitCode: 0) }
            signals.append(source)
            source.resume()
        }
    }

    func stopAndFinish(reason: String, exitCode: Int32) {
        guard !finished else { return }
        if process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(5)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
            if process.isRunning {
                _ = kill(process.processIdentifier, SIGKILL)
                let forced = Date().addingTimeInterval(3)
                while process.isRunning && Date() < forced { Thread.sleep(forTimeInterval: 0.05) }
            }
        }
        guard !process.isRunning else { exit(3) }
        if launched { process.waitUntilExit() }
        finish(reason: reason, exitCode: exitCode)
    }

    private func finish(reason: String, exitCode: Int32) {
        guard !finished else { return }
        finished = true
        if !process.isRunning {
            try? write(["schema": 1, "core_pid": launched ? Int(process.processIdentifier) : 0,
                        "supervisor_pid": Int(getpid()), "instance": run.lastPathComponent,
                        "core_exited": true, "reason": reason], to: run.appendingPathComponent("supervisor.done.json"))
        }
        exit(exitCode == 0 ? 0 : 1)
    }

    private func write(_ value: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
