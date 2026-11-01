import Foundation
import CryptoKit
import Darwin

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Platform implementation. One queue owns the process, session and private files.
/// Public callbacks return only CoreSnapshot, which cannot contain credentials.
final class CoreController: @unchecked Sendable {
    static let version = "v4.2.8"
    static let sourceDigest = "f8ced5c3e34de944ddbfc187181b9666cfa076f02281d38e301dc56eaa82933e"
    private let queue = DispatchQueue(label: "dev.privatevault.w01.core")
    private let guardLock = NSLock()
    private var stopEpoch = 0
    private var current = CoreSnapshot(phase: .stopped, message: "本机服务尚未启动")
    var onSnapshot: ((CoreSnapshot) -> Void)?

    private let binary: URL
    private let expectedDigest: String
    private let root: URL
    private let fixtureData: Data
    private let portAllocator: (() throws -> Int)?
    private let supervisor: URL?
    private let supervisorDigest: String?
    private var child: Process?
    private var keepAlive: FileHandle?
    private var corePID: Int32?
    private var auxiliary: Process?
    private var runDirectory: URL?
    private var port = 0
    private var password = ""
    private var serverKey = ""
    private var token = ""
    private var fileLock: Int32 = -1
    private var stage = "idle"
    private var commandFailure: [String: Any] = [:]
    private let http: URLSession
    private let redirects = NoRedirects()

    init(binary: URL, expectedDigest: String, root: URL, fixtureData: Data,
         portAllocator: (() throws -> Int)? = nil, supervisor: URL? = nil, supervisorDigest: String? = nil) {
        self.binary = binary.standardizedFileURL
        self.expectedDigest = expectedDigest
        self.root = root.standardizedFileURL
        self.fixtureData = fixtureData
        self.portAllocator = portAllocator
        self.supervisor = supervisor
        self.supervisorDigest = supervisorDigest
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 4
        http = URLSession(configuration: config, delegate: redirects, delegateQueue: nil)
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("active.json").path) {
            current = .init(phase: .stopped, message: "检测到已有服务记录，启动时会先核对。", errorCode: "recovery_pending")
        }
    }

    func snapshot() -> CoreSnapshot { locked { current } }

    func start(completion: @escaping (CoreSnapshot) -> Void) {
        let epoch = locked { stopEpoch }
        queue.async {
            if self.snapshot().phase == .ready { completion(self.snapshot()); return }
            do {
                try self.check(epoch)
                if self.child != nil && !self.tearDown() { throw CoreFailure.stopFailed }
                self.publish(.init(phase: .starting, message: "正在准备本机服务…"))
                self.stage = "prepare_private_root"
                self.commandFailure = [:]
                try self.prepareRoot()
                self.stage = "verify_binary"
                try self.verifyBinary()
                self.stage = "reconcile_previous_run"
                try self.reconcilePreviousRun()
                try self.check(epoch)
                let deadline = Date().addingTimeInterval(30)
                try self.launch(epoch: epoch, deadline: deadline)
                completion(self.snapshot())
            } catch {
                let failure = error as? CoreFailure ?? .launch
                if self.fileLock >= 0 {
                    var diagnostic: [String: Any] = ["stage": self.stage, "code": failure.code]
                    diagnostic["command_failure"] = self.commandFailure
                    try? self.writeJSON(diagnostic, self.root.appendingPathComponent("diagnostic.json"))
                }
                let cleaned = self.tearDown()
                self.publish(.init(phase: failure.code == "cancelled" && cleaned ? .stopped : .failed,
                                   message: cleaned ? failure.message : CoreFailure.stopFailed.message,
                                   errorCode: cleaned ? failure.code : CoreFailure.stopFailed.code))
                completion(self.snapshot())
            }
        }
    }

    func stop(completion: @escaping (CoreSnapshot) -> Void) {
        // Invalidates every start queued before this stop, including a probe in progress.
        locked { stopEpoch += 1 }
        queue.async {
            self.publish(.init(phase: .stopping, message: "正在停止本机服务…"))
            let stopped = self.tearDown()
            self.publish(.init(phase: stopped ? .stopped : .failed,
                               message: stopped ? "本机服务已停止" : CoreFailure.stopFailed.message,
                               errorCode: stopped ? nil : CoreFailure.stopFailed.code))
            completion(self.snapshot())
        }
    }

    func readFixture(completion: @escaping (CoreSnapshot) -> Void) {
        queue.async {
            do {
                guard self.snapshot().phase == .ready, self.child?.isRunning == true else {
                    throw CoreFailure.stopped
                }
                let fixture = try self.verifyFixture()
                self.publish(.init(phase: .ready, message: "测试图片已读取，内容校验一致", version: Self.version,
                                   fixture: fixture))
            } catch {
                let failure = error as? CoreFailure ?? .fixture
                _ = self.tearDown()
                self.publish(.init(phase: .failed, message: failure.message, errorCode: failure.code))
            }
            completion(self.snapshot())
        }
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        guardLock.lock(); defer { guardLock.unlock() }; return try body()
    }

    private func publish(_ next: CoreSnapshot) {
        let updated = locked { () -> CoreSnapshot in
            var value = next
            value.revision = current.revision + 1
            current = value
            return value
        }
        onSnapshot?(updated)
    }

    private func check(_ epoch: Int, deadline: Date? = nil) throws {
        guard locked({ stopEpoch == epoch }) else { throw CoreFailure.cancelled }
        if let deadline, Date() > deadline { throw CoreFailure.timeout }
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func prepareRoot() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: root.path) {
            let a = try fm.attributesOfItem(atPath: root.path)
            guard a[.type] as? FileAttributeType == .typeDirectory,
                  (a[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { throw CoreFailure.storage }
            let marker = root.appendingPathComponent("owner.json")
            if fm.fileExists(atPath: marker.path) {
                let owner = try readJSON(marker)
                guard owner["application"] as? String == "dev.privatevault.w01", owner["schema"] as? Int == 1 else {
                    throw CoreFailure.foreign
                }
            } else {
                guard (try fm.contentsOfDirectory(atPath: root.path)).isEmpty else { throw CoreFailure.foreign }
            }
        } else {
            try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        if fileLock == -1 {
            fileLock = Darwin.open(root.appendingPathComponent("host.lock").path,
                                   O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
            guard fileLock >= 0 else { throw CoreFailure.storage }
            guard flock(fileLock, LOCK_EX | LOCK_NB) == 0 else {
                close(fileLock); fileLock = -1; throw CoreFailure.busy
            }
        }
        try writeJSON(["application": "dev.privatevault.w01", "schema": 1], root.appendingPathComponent("owner.json"))
        guard fixtureData.count > 0, fixtureData.count < 65536 else { throw CoreFailure.fixture }
    }

    private func verifyBinary() throws {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: binary.path) else { throw CoreFailure.missingCore }
        guard try fm.attributesOfItem(atPath: binary.path)[.type] as? FileAttributeType == .typeRegular else {
            throw CoreFailure.integrity
        }
        // Hash before executing any command, including `version`.
        let handle = try FileHandle(forReadingFrom: binary)
        defer { try? handle.close() }
        var hash = SHA256()
        while let block = try handle.read(upToCount: 1024 * 1024), !block.isEmpty { hash.update(data: block) }
        let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == expectedDigest else { throw CoreFailure.integrity }
        if let supervisor {
            guard let supervisorDigest, fm.isExecutableFile(atPath: supervisor.path),
                  try fm.attributesOfItem(atPath: supervisor.path)[.type] as? FileAttributeType == .typeRegular,
                  Self.digest(try Data(contentsOf: supervisor)) == supervisorDigest else { throw CoreFailure.integrity }
        }
        stage = "verify_version"
        let output = try command(binary, ["version"], timeout: 5)
        guard output.contains("Version: v4.2.8"), output.contains("Commit ID: 25e4eb6"),
              output.contains("darwin/arm64") else { throw CoreFailure.incompatible }
    }

    private func launch(epoch: Int, deadline: Date) throws {
        let fm = FileManager.default
        for attempt in 0..<3 {
            try check(epoch, deadline: deadline)
            let run = root.appendingPathComponent("runs/" + UUID().uuidString)
            try fm.createDirectory(at: run.appendingPathComponent("fixture"), withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            runDirectory = run
            try privateWrite(fixtureData, run.appendingPathComponent("fixture/样本.png"))
            password = Self.randomSecret()
            serverKey = Self.randomSecret()
            port = try portAllocator?() ?? Self.unusedPort()
            try writeConfiguration(run: run)
            try privateWrite(Data(password.utf8), run.appendingPathComponent("session.secret"))
            stage = "initialize_test_database"
            _ = try command(binary, ["--data", run.path, "--config", run.appendingPathComponent("config.json").path, "admin"],
                            timeout: min(10, deadline.timeIntervalSinceNow), capture: false,
                            environment: ["OPENLIST_ADMIN_PASSWORD": password])
            try check(epoch, deadline: deadline)
            let p = Process()
            if let supervisor {
                let pipe = Pipe()
                _ = fcntl(pipe.fileHandleForWriting.fileDescriptor, F_SETFD, FD_CLOEXEC)
                keepAlive = pipe.fileHandleForWriting
                p.standardInput = pipe
                p.executableURL = supervisor
                p.arguments = [binary.path, run.path, run.appendingPathComponent("config.json").path,
                               run.appendingPathComponent("supervisor.json").path]
            } else {
                p.executableURL = binary
                p.arguments = ["--data", run.path, "--config", run.appendingPathComponent("config.json").path, "server"]
            }
            p.currentDirectoryURL = run
            p.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TMPDIR": run.appendingPathComponent("temp").path]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            stage = "start_core_process"
            try p.run()
            child = p
            let managedPID = p.processIdentifier
            p.terminationHandler = { [weak self] _ in
                guard let self else { return }
                self.queue.async {
                    if self.child?.processIdentifier == managedPID, self.snapshot().phase == .ready {
                        let stopped = self.tearDown()
                        self.publish(.init(phase: .failed, message: stopped ? "本机服务意外停止，可以重新启动。" : CoreFailure.stopFailed.message,
                                           errorCode: stopped ? "core_exited" : CoreFailure.stopFailed.code))
                    }
                }
            }
            if supervisor != nil {
                while p.isRunning && corePID == nil {
                    try check(epoch, deadline: deadline)
                    if let metadata = try? readJSON(run.appendingPathComponent("supervisor.json")),
                       metadata["instance"] as? String == run.lastPathComponent,
                       metadata["supervisor_pid"] as? Int == Int(managedPID),
                       let pid = metadata["core_pid"] as? Int, pid > 1 {
                        corePID = Int32(pid)
                    } else { Thread.sleep(forTimeInterval: 0.02) }
                }
            } else { corePID = managedPID }
            guard let pid = corePID else { throw CoreFailure.launch }
            var listening = false
            stage = "verify_owned_listener"
            while p.isRunning {
                try check(epoch, deadline: deadline)
                if (try? ownsEndpoint(pid: pid, port: port)) == true { listening = true; break }
                // A competitor may bind after our free-port selection. Recheck our
                // listener before treating the occupied port as a failed attempt.
                if Self.portIsBound(port) && (try? ownsEndpoint(pid: pid, port: port)) != true { break }
                Thread.sleep(forTimeInterval: 0.1)
            }
            if !listening {
                _ = tearDownRun()
                if attempt < 2 { continue }
                throw CoreFailure.launch
            }
            // Persist identity only after the listener belongs to this exact child.
            stage = "identify_child_process"
            var identity: [String: Any] = ["schema": 1, "pid": Int(pid), "port": port,
                "run": run.path, "binary": binary.path, "digest": expectedDigest,
                "started": try ownedCoreStamp(pid)]
            if supervisor != nil {
                identity["supervised"] = true
                identity["supervisor_pid"] = Int(managedPID)
            }
            try writeJSON(identity, root.appendingPathComponent("active.json"))
            try check(epoch, deadline: deadline)
            stage = "authenticate_core"
            let login = try api("/api/auth/login", body: ["username": "admin", "password": password], authorized: false)
            guard let t = (login["data"] as? [String: Any])?["token"] as? String,
                  Self.verifyLocalToken(t, key: serverKey) else { throw CoreFailure.auth }
            token = t
            let me = try api("/api/me", method: "GET")
            guard (me["data"] as? [String: Any])?["role"] as? Int == 2 else { throw CoreFailure.auth }
            stage = "configure_local_fixture"
            try hardenAndMount(run: run)
            try check(epoch, deadline: deadline)
            stage = "verify_fixture_content"
            let fixture = try verifyFixture()
            try check(epoch, deadline: deadline)
            guard p.isRunning, try ownsEndpoint(pid: pid, port: port) else { throw CoreFailure.launch }
            try? FileManager.default.removeItem(at: root.appendingPathComponent("diagnostic.json"))
            self.publish(.init(phase: .ready, message: "本机服务已就绪，测试图片校验通过", version: Self.version, fixture: fixture))
            return
        }
        throw CoreFailure.launch
    }

    private func hardenAndMount(run: URL) throws {
        let users = try api("/api/admin/user/list", method: "GET")
        guard let content = (users["data"] as? [String: Any])?["content"] as? [[String: Any]],
              var guest = content.first(where: { $0["role"] as? Int == 1 }) else { throw CoreFailure.incompatible }
        guest["disabled"] = true; guest["password"] = ""
        _ = try api("/api/admin/user/update", body: guest)
        let settings = try api("/api/admin/setting/list", method: "GET")
        guard let items = settings["data"] as? [[String: Any]], items.contains(where: { $0["key"] as? String == "sign_all" }) else {
            throw CoreFailure.incompatible
        }
        let changes = items.compactMap { item -> [String: Any]? in
            guard let key = item["key"] as? String,
                  ["sign_all", "media_enabled", "transcode_enabled", "auto_update_index"].contains(key) else { return nil }
            var changed = item; changed["value"] = key == "sign_all" ? "true" : "false"; return changed
        }
        _ = try api("/api/admin/setting/save", body: changes)
        let addition: [String: Any] = ["root_folder_path": run.appendingPathComponent("fixture").path,
            "thumbnail": false, "show_hidden": false, "mkdir_perm": "700", "directory_size": false]
        let additionText = String(data: try JSONSerialization.data(withJSONObject: addition), encoding: .utf8)!
        _ = try api("/api/admin/storage/create", body: ["mount_path": "/w01", "driver": "Local", "order": 0,
            "addition": additionText, "cache_expiration": 0, "disabled": false, "enable_sign": true,
            "web_proxy": true, "webdav_policy": "proxy", "remark": "PrivateVault W01 synthetic fixture only"])
        let denied = try api("/api/fs/list", body: ["path": "/w01", "password": "", "refresh": true],
                             authorized: false, requireSuccess: false)
        guard [401, 403].contains(denied["code"] as? Int ?? -1) else { throw CoreFailure.auth }
        let deniedAdmin = try api("/api/admin/user/list", method: "GET", authorized: false, requireSuccess: false)
        guard [401, 403].contains(deniedAdmin["code"] as? Int ?? -1) else { throw CoreFailure.auth }
        let (_, response) = try request("/p/w01/样本.png", method: "GET", authorized: false)
        guard [401, 403].contains(response.statusCode) else { throw CoreFailure.auth }
    }

    private func verifyFixture() throws -> FixtureResult {
        let listed = try api("/api/fs/list", body: ["path": "/w01", "password": "", "refresh": true, "page": 1, "per_page": 10])
        guard let files = (listed["data"] as? [String: Any])?["content"] as? [[String: Any]],
              files.count == 1, files[0]["name"] as? String == "样本.png",
              files[0]["size"] as? Int == fixtureData.count else { throw CoreFailure.fixture }
        let got = try api("/api/fs/get", body: ["path": "/w01/样本.png", "password": ""])
        guard let sign = (got["data"] as? [String: Any])?["sign"] as? String, !sign.isEmpty else { throw CoreFailure.auth }
        let (data, response) = try request("/p/w01/样本.png", method: "GET", query: [URLQueryItem(name: "sign", value: sign)])
        guard response.statusCode == 200, data == fixtureData else { throw CoreFailure.fixture }
        return FixtureResult(name: "样本.png", byteLength: data.count, sha256: Self.digest(data), bytesBase64: data.base64EncodedString())
    }

    private func writeConfiguration(run: URL) throws {
        let config: [String: Any] = ["cdn": "", "site_url": "http://127.0.0.1:\(port)",
            "jwt_secret": serverKey, "token_expires_in": 1,
            "scheme": ["address": "127.0.0.1", "http_port": port, "https_port": -1, "force_https": false,
                       "unix_file": "", "enable_h2c": false, "enable_h3": false],
            "database": ["type": "sqlite3", "db_file": run.appendingPathComponent("data.db").path, "table_prefix": "x_"],
            "temp_dir": run.appendingPathComponent("temp").path,
            "log": ["enable": false], "s3": ["enable": false], "ftp": ["enable": false],
            "sftp": ["enable": false], "mcp": ["enable": false], "delayed_start": 0,
            "last_launched_version": Self.version]
        try writeJSON(config, run.appendingPathComponent("config.json"))
    }

    private func api(_ path: String, method: String = "POST", body: Any? = nil,
                     authorized: Bool = true, requireSuccess: Bool = true) throws -> [String: Any] {
        let (data, response) = try request(path, method: method, body: body, authorized: authorized)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CoreFailure.incompatible }
        if requireSuccess && (response.statusCode != 200 || json["code"] as? Int != 200) { throw CoreFailure.auth }
        return json
    }

    private func request(_ path: String, method: String, body: Any? = nil, authorized: Bool = true,
                         query: [URLQueryItem] = []) throws -> (Data, HTTPURLResponse) {
        var url = URLComponents(); url.scheme = "http"; url.host = "127.0.0.1"; url.port = port; url.path = path
        if !query.isEmpty { url.queryItems = query }
        guard let target = url.url else { throw CoreFailure.incompatible }
        var request = URLRequest(url: target); request.httpMethod = method; request.timeoutInterval = 3
        if authorized && !token.isEmpty { request.setValue(token, forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let completed = DispatchSemaphore(value: 0)
        let box = ResponseBox()
        let task = http.dataTask(with: request) { data, response, error in
            box.data = data; box.response = response as? HTTPURLResponse; box.failed = error != nil; completed.signal()
        }
        task.resume()
        guard completed.wait(timeout: .now() + 4) == .success else { task.cancel(); throw CoreFailure.timeout }
        guard !box.failed, let data = box.data, data.count <= 65536, let response = box.response else { throw CoreFailure.incompatible }
        return (data, response)
    }

    private func reconcilePreviousRun() throws {
        let marker = root.appendingPathComponent("active.json")
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        let identity = try readJSON(marker)
        guard identity["schema"] as? Int == 1,
              let pid = identity["pid"] as? Int, pid > 1, let savedPort = identity["port"] as? Int,
              let runPath = identity["run"] as? String, let stamp = identity["started"] as? String,
              identity["binary"] as? String == binary.path, identity["digest"] as? String == expectedDigest else { throw CoreFailure.foreign }
        let run = URL(fileURLWithPath: runPath).standardizedFileURL
        guard run.deletingLastPathComponent().path == root.appendingPathComponent("runs").path,
              UUID(uuidString: run.lastPathComponent) != nil else { throw CoreFailure.foreign }
        if identity["supervised"] as? Bool == true {
            guard let supervisorPID = identity["supervisor_pid"] as? Int, supervisorPID > 1 else { throw CoreFailure.foreign }
            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline {
                if let done = try? readJSON(run.appendingPathComponent("supervisor.done.json")),
                   done["instance"] as? String == run.lastPathComponent,
                   done["core_pid"] as? Int == pid, done["core_exited"] as? Bool == true,
                   done["supervisor_pid"] as? Int == supervisorPID,
                   (try? processStamp(Int32(pid))) != stamp {
                    try FileManager.default.removeItem(at: run)
                    try FileManager.default.removeItem(at: marker)
                    return
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
            throw CoreFailure(code: "previous_core_stopping", message: "上次服务尚未确认退出，请稍后重试；恢复信息已保留。")
        }
        if kill(pid_t(pid), 0) == 0 {
            let attributes = try FileManager.default.attributesOfItem(atPath: run.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { throw CoreFailure.foreign }
            let config = try readJSON(run.appendingPathComponent("config.json"))
            guard let key = config["jwt_secret"] as? String, key.count >= 32,
                  let scheme = config["scheme"] as? [String: Any], scheme["address"] as? String == "127.0.0.1",
                  scheme["http_port"] as? Int == savedPort else { throw CoreFailure.foreign }
            serverKey = key
            port = savedPort
            password = try String(contentsOf: run.appendingPathComponent("session.secret"), encoding: .utf8)
            guard try processStamp(pid_t(pid)) == stamp, try ownsEndpoint(pid: pid_t(pid), port: savedPort) else {
                throw CoreFailure.foreign
            }
            let auth = try api("/api/auth/login", body: ["username": "admin", "password": password], authorized: false)
            // The unique credential stored in this validated run directory binds
            // the authenticated core to that directory without reading argv/env.
            guard let recoveredToken = (auth["data"] as? [String: Any])?["token"] as? String,
                  Self.verifyLocalToken(recoveredToken, key: serverKey),
                  try processStamp(pid_t(pid)) == stamp else { throw CoreFailure.foreign }
            guard kill(pid_t(pid), SIGTERM) == 0 else { throw CoreFailure.stopFailed }
            let deadline = Date().addingTimeInterval(5)
            while kill(pid_t(pid), 0) == 0 && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
            guard kill(pid_t(pid), 0) != 0 else { throw CoreFailure.stopFailed }
        } else if errno != ESRCH { throw CoreFailure.foreign }
        try FileManager.default.removeItem(at: run)
        try FileManager.default.removeItem(at: marker)
        password = ""; serverKey = ""; token = ""; port = 0
    }

    private func tearDownRun() -> Bool {
        if let auxiliary, !terminateOwned(auxiliary) { return false }
        auxiliary = nil
        if supervisor != nil {
            try? keepAlive?.close()
            keepAlive = nil
        }
        if supervisor != nil, child != nil {
            let deadline = Date().addingTimeInterval(10)
            while child?.isRunning == true && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
            guard child?.isRunning != true, let runDirectory,
                  let done = try? readJSON(runDirectory.appendingPathComponent("supervisor.done.json")),
                  done["instance"] as? String == runDirectory.lastPathComponent,
                  done["core_exited"] as? Bool == true,
                  done["supervisor_pid"] as? Int == child.map({ Int($0.processIdentifier) }),
                  corePID == nil || done["core_pid"] as? Int == Int(corePID!) else { return false }
        } else if let process = child, process.isRunning {
            guard terminateOwned(process) else { return false }
        }
        child = nil; corePID = nil; token = ""; password = ""; serverKey = ""; port = 0
        if let runDirectory {
            try? FileManager.default.removeItem(at: runDirectory)
            let marker = root.appendingPathComponent("active.json")
            if let identity = try? readJSON(marker), identity["run"] as? String == runDirectory.path {
                try? FileManager.default.removeItem(at: marker)
            }
        }
        self.runDirectory = nil
        return true
    }

    private func tearDown() -> Bool {
        let result = tearDownRun()
        if result && fileLock >= 0 { flock(fileLock, LOCK_UN); close(fileLock); fileLock = -1 }
        return result
    }

    private func ownsEndpoint(pid: Int32, port: Int) throws -> Bool {
        // Kernel FD inspection is useful outside App Sandbox, but is denied
        // within it. In that case retain basic kernel process identity and
        // prove possession of the per-run private JWT key using CryptoKit.
        let needed = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard needed > 0, needed < 1024 * 1024 else {
            _ = try ownedCoreStamp(pid)
            guard !password.isEmpty, serverKey.count >= 32, port == self.port else { return false }
            let response = try api("/api/auth/login", body: ["username": "admin", "password": password], authorized: false)
            guard let proof = (response["data"] as? [String: Any])?["token"] as? String,
                  Self.verifyLocalToken(proof, key: serverKey) else {
                commandFailure = ["api": "private_endpoint_proof", "valid": false]
                throw CoreFailure.foreign
            }
            token = proof
            return true
        }
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(needed) / MemoryLayout<proc_fdinfo>.stride + 32)
        let actual = descriptors.withUnsafeMutableBytes { bytes in
            proc_pidinfo(pid, PROC_PIDLISTFDS, 0, bytes.baseAddress, Int32(bytes.count))
        }
        guard actual > 0, actual < descriptors.count * MemoryLayout<proc_fdinfo>.stride else { throw CoreFailure.foreign }
        var listeners = 0
        for descriptor in descriptors.prefix(Int(actual) / MemoryLayout<proc_fdinfo>.stride) where descriptor.proc_fdtype == PROX_FDTYPE_SOCKET {
            var info = socket_fdinfo()
            let result = proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDSOCKETINFO, &info, Int32(MemoryLayout<socket_fdinfo>.size))
            guard result == MemoryLayout<socket_fdinfo>.size else {
                commandFailure = ["api": "proc_pidfdinfo_socket", "errno": Int(errno)]
                throw CoreFailure.foreign
            }
            guard info.psi.soi_kind == SOCKINFO_TCP, info.psi.soi_proto.pri_tcp.tcpsi_state == TSI_S_LISTEN else { continue }
            listeners += 1
            let socket = info.psi.soi_proto.pri_tcp.tcpsi_ini
            guard info.psi.soi_family == AF_INET,
                  socket.insi_laddr.ina_46.i46a_addr4.s_addr == inet_addr("127.0.0.1"),
                  UInt16(bigEndian: UInt16(truncatingIfNeeded: socket.insi_lport)) == UInt16(port) else { return false }
        }
        return listeners == 1
    }

    /// Validate the stock core's documented HS256 token; never accept an
    /// algorithm chosen by an untrusted token or a signature under another key.
    static func verifyLocalToken(_ value: String, key: String, now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard value.count <= 8192, key.count >= 32 else { return false }
        let pieces = value.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3,
              let headerData = decodeURLBase64(String(pieces[0])), headerData.count <= 1024,
              let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              header["alg"] as? String == "HS256",
              let signature = decodeURLBase64(String(pieces[2])), signature.count == 32,
              HMAC<SHA256>.isValidAuthenticationCode(signature,
                authenticating: Data("\(pieces[0]).\(pieces[1])".utf8), using: SymmetricKey(data: Data(key.utf8))),
              let claimsData = decodeURLBase64(String(pieces[1])),
              let claims = try? JSONSerialization.jsonObject(with: claimsData) as? [String: Any],
              claims["username"] as? String == "admin",
              let expires = claims["exp"] as? Double, let issued = claims["iat"] as? Double,
              let notBefore = claims["nbf"] as? Double else { return false }
        return expires > now && expires <= now + 3660 && issued <= now + 30 && issued >= now - 300 && notBefore <= now + 30
    }

    private static func decodeURLBase64(_ value: String) -> Data? {
        var normalized = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        normalized += String(repeating: "=", count: (4 - normalized.count % 4) % 4)
        return Data(base64Encoded: normalized)
    }

    private func ownedCoreStamp(_ pid: Int32) throws -> String {
        if let supervisor, let child, child.isRunning, let runDirectory {
            _ = try processStamp(child.processIdentifier, expectedBinary: supervisor)
            let info = try readJSON(runDirectory.appendingPathComponent("supervisor.json"))
            guard info["instance"] as? String == runDirectory.lastPathComponent,
                  info["supervisor_pid"] as? Int == Int(child.processIdentifier),
                  info["core_pid"] as? Int == Int(pid), info["core_binary"] as? String == binary.path,
                  let stamp = info["started"] as? String else { throw CoreFailure.foreign }
            return stamp
        }
        return try processStamp(pid)
    }

    private func processStamp(_ pid: Int32, expectedBinary: URL? = nil) throws -> String {
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size,
              info.pbi_uid == getuid(), info.pbi_pid == UInt32(pid) else { throw CoreFailure.foreign }
        // The SDK defines PROC_PIDPATHINFO_MAXSIZE as 4*MAXPATHLEN; the compound
        // macro is not imported by Swift, so use that documented expression.
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let pathLength = path.withUnsafeMutableBufferPointer { bytes in
            proc_pidpath(pid, bytes.baseAddress, UInt32(bytes.count))
        }
        guard pathLength > 0 else { throw CoreFailure.foreign }
        let executable = URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath()
        guard executable == (expectedBinary ?? binary).resolvingSymlinksInPath() else { throw CoreFailure.foreign }
        return "\(info.pbi_start_tvsec).\(info.pbi_start_tvusec)|\(executable.path)"
    }

    private func command(_ executable: URL, _ arguments: [String], timeout: TimeInterval,
                         capture: Bool = true, environment: [String: String] = [:]) throws -> String {
        guard timeout > 0 else { throw CoreFailure.timeout }
        let p = Process(); p.executableURL = executable; p.arguments = arguments
        p.currentDirectoryURL = runDirectory ?? root
        p.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"].merging(environment) { _, new in new }
        let pipe = Pipe(); p.standardOutput = capture ? pipe : FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() }
        catch {
            let code = error as NSError
            commandFailure = ["program": executable.lastPathComponent, "domain": code.domain, "code": code.code]
            throw error
        }
        auxiliary = p
        defer { if !p.isRunning { auxiliary = nil } }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if p.isRunning {
            guard terminateOwned(p) else { throw CoreFailure.stopFailed }
            throw CoreFailure.timeout
        }
        guard p.terminationStatus == 0 else {
            commandFailure = ["program": executable.lastPathComponent, "exit": Int(p.terminationStatus),
                              "reason": p.terminationReason == .uncaughtSignal ? "signal" : "exit"]
            throw CoreFailure.launch
        }
        let data = capture ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
        guard data.count < 65536 else { throw CoreFailure.incompatible }
        return String(decoding: data, as: UTF8.self)
    }

    private func terminateOwned(_ process: Process) -> Bool {
        guard process.isRunning else { return true }
        process.terminate()
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            // Only a live Process handle created by this controller is signalled.
            _ = kill(process.processIdentifier, SIGKILL)
            let killed = Date().addingTimeInterval(3)
            while process.isRunning && Date() < killed { Thread.sleep(forTimeInterval: 0.05) }
        }
        return !process.isRunning
    }

    private func privateWrite(_ data: Data, _ url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func writeJSON(_ value: [String: Any], _ url: URL) throws {
        try privateWrite(JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), url)
    }
    private func readJSON(_ url: URL) throws -> [String: Any] {
        guard try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType == .typeRegular,
              let value = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else { throw CoreFailure.foreign }
        return value
    }
    private static func randomSecret() -> String {
        var rng = SystemRandomNumberGenerator()
        return Data((0..<32).map { _ in UInt8.random(in: 0...255, using: &rng) }).base64EncodedString()
    }
    private static func unusedPort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw CoreFailure.launch }
        defer { close(fd) }
        var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET); address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else { throw CoreFailure.launch }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard named == 0 else { throw CoreFailure.launch }
        return Int(UInt16(bigEndian: address.sin_port))
    }

    private static func portIsBound(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET); address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = UInt16(port).bigEndian
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        return result != 0 && errno == EADDRINUSE
    }
}

private final class ResponseBox: @unchecked Sendable {
    var data: Data?
    var response: HTTPURLResponse?
    var failed = false
}
