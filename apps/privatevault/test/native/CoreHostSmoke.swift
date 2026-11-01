import Foundation
import Darwin
import CryptoKit

@main
struct CoreHostSmoke {
    static func call(_ action: (@escaping (CoreSnapshot) -> Void) -> Void) async -> CoreSnapshot {
        await withCheckedContinuation { continuation in action { continuation.resume(returning: $0) } }
    }

    static func main() async {
        umask(0o077)
        guard CommandLine.arguments.count == 5 else {
            print("Usage: native-check <core> <private-test-root> <fixture> <smoke|suite|hold>")
            exit(2)
        }
        let binary = URL(fileURLWithPath: CommandLine.arguments[1])
        let root = URL(fileURLWithPath: CommandLine.arguments[2])
        guard let bytes = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3])) else { exit(2) }
        let mode = CommandLine.arguments[4]
        var results: [[String: Any]] = []
        func record(_ name: String, _ pass: Bool, _ snapshot: CoreSnapshot? = nil) {
            var row: [String: Any] = ["check": name, "passed": pass]
            if let snapshot {
                row["phase"] = snapshot.phase.rawValue
                if let code = snapshot.errorCode { row["error_code"] = code }
                if let fixture = snapshot.fixture { row["fixture_bytes"] = fixture.byteLength; row["fixture_sha256"] = fixture.sha256 }
            }
            results.append(row)
            if let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]),
               let text = String(data: data, encoding: .utf8) { print(text) }
        }
        let supervisor = ProcessInfo.processInfo.environment["PV_W01_SUPERVISOR_PATH"].map { URL(fileURLWithPath: $0) }
        let supervisorHash = supervisor.flatMap { try? Data(contentsOf: $0) }.map(CoreController.digest)
        let host = CoreController(binary: binary, expectedDigest: CoreController.sourceDigest, root: root, fixtureData: bytes,
                                  supervisor: supervisor, supervisorDigest: supervisorHash)
        let first = await call(host.start)
        record("authenticated_local_read", first.phase == .ready && first.fixture?.sha256 == CoreController.digest(bytes), first)
        if first.phase != .ready {
            _ = await call(host.stop)
            exit(1)
        }
        if mode == "hold" {
            fflush(stdout)
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            _ = await call(host.stop)
            return
        }
        if mode == "suite" {
            let proofKey = String(repeating: "synthetic-unit-key-", count: 3)
            let now = Date().timeIntervalSince1970
            func localToken(algorithm: String = "HS256", expires: TimeInterval? = nil) -> String {
                func encoded(_ data: Data) -> String {
                    data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                        .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
                }
                let header = encoded(try! JSONSerialization.data(withJSONObject: ["alg": algorithm, "typ": "JWT"], options: [.sortedKeys]))
                let claims: [String: Any] = ["username": "admin", "exp": Int(expires ?? (now + 3600)), "iat": Int(now), "nbf": Int(now)]
                let payload = encoded(try! JSONSerialization.data(withJSONObject: claims, options: [.sortedKeys]))
                let message = header + "." + payload
                let signature = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: SymmetricKey(data: Data(proofKey.utf8)))
                return message + "." + encoded(Data(signature))
            }
            let proof = localToken()
            let pieces = proof.split(separator: ".").map(String.init)
            let tampered = pieces[0] + ".e30." + pieces[2]
            record("jwt_valid_and_tamper_rejection", CoreController.verifyLocalToken(proof, key: proofKey, now: now) && !CoreController.verifyLocalToken(tampered, key: proofKey, now: now))
            record("jwt_wrong_key_rejected", !CoreController.verifyLocalToken(proof, key: String(repeating: "other-unit-key", count: 4), now: now))
            record("jwt_algorithm_substitution_rejected", !CoreController.verifyLocalToken(localToken(algorithm: "none"), key: proofKey, now: now))
            record("jwt_expired_token_rejected", !CoreController.verifyLocalToken(localToken(expires: now - 1), key: proofKey, now: now))
            let duplicate = await call(host.start)
            record("idempotent_start", duplicate.phase == .ready, duplicate)
            let second = CoreController(binary: binary, expectedDigest: CoreController.sourceDigest, root: root, fixtureData: bytes)
            let busy = await call(second.start)
            let stillReadable = await call(host.readFixture)
            record("second_host_cannot_take_over", busy.errorCode == "instance_busy" && stillReadable.phase == .ready && FileManager.default.fileExists(atPath: root.appendingPathComponent("active.json").path), busy)
            _ = await call(second.stop)
            if let data = try? Data(contentsOf: root.appendingPathComponent("active.json")),
               let identity = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let pid = identity["pid"] as? Int {
                _ = kill(pid_t(pid), SIGKILL)
                for _ in 0..<60 where host.snapshot().phase != .failed { try? await Task.sleep(nanoseconds: 50_000_000) }
                record("core_exit_detected", host.snapshot().phase == .failed, host.snapshot())
                let restarted = await call(host.start)
                record("restart_after_core_exit", restarted.phase == .ready, restarted)
            } else { record("core_exit_detected", false) }
        }
        let stopped = await call(host.stop)
        record("stop_releases_run", stopped.phase == .stopped && !FileManager.default.fileExists(atPath: root.appendingPathComponent("active.json").path), stopped)
        if mode == "suite" {
            let twice = await call(host.stop)
            record("idempotent_stop", twice.phase == .stopped, twice)
            for index in 1...2 {
                let started = await call(host.start)
                let stopped = await call(host.stop)
                record("repeat_cycle_\(index)", started.phase == .ready && stopped.phase == .stopped, stopped)
            }
            let integrity = CoreController(binary: binary, expectedDigest: String(repeating: "0", count: 64), root: root.appendingPathComponent("integrity"), fixtureData: bytes)
            let rejected = await call(integrity.start)
            record("bad_digest_rejected", rejected.errorCode == "integrity_mismatch", rejected)
            _ = await call(integrity.stop)
            if let supervisor {
                let invalidSupervisor = CoreController(binary: binary, expectedDigest: CoreController.sourceDigest,
                    root: root.appendingPathComponent("supervisor-integrity"), fixtureData: bytes,
                    supervisor: supervisor, supervisorDigest: String(repeating: "0", count: 64))
                let rejectedSupervisor = await call(invalidSupervisor.start)
                record("supervisor_bad_digest_rejected", rejectedSupervisor.errorCode == "integrity_mismatch", rejectedSupervisor)
                _ = await call(invalidSupervisor.stop)
            }
            let missing = CoreController(binary: root.appendingPathComponent("not-a-core"), expectedDigest: CoreController.sourceDigest, root: root.appendingPathComponent("missing"), fixtureData: bytes)
            let absent = await call(missing.start)
            record("missing_core_rejected", absent.errorCode == "missing_core", absent)
            _ = await call(missing.stop)
            let race = await withCheckedContinuation { (continuation: CheckedContinuation<[CoreSnapshot], Never>) in
                let group = DispatchGroup()
                let values = SnapshotBox()
                group.enter()
                host.start { value in values.append(value); group.leave() }
                group.enter()
                host.stop { value in values.append(value); group.leave() }
                group.notify(queue: .global()) { continuation.resume(returning: values.values) }
            }
            record("stop_during_start", race.count == 2 && host.snapshot().phase == .stopped, host.snapshot())
            let afterRace = await call(host.start)
            record("restart_after_cancel", afterRace.phase == .ready, afterRace)
            _ = await call(host.stop)

            let foreignRoot = root.appendingPathComponent("foreign")
            try? FileManager.default.createDirectory(at: foreignRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let owner = try! JSONSerialization.data(withJSONObject: ["application": "dev.privatevault.w01", "schema": 1])
            try? owner.write(to: foreignRoot.appendingPathComponent("owner.json"))
            let foreignMarker = Data("{\"pid\":1,\"schema\":1}".utf8)
            try? foreignMarker.write(to: foreignRoot.appendingPathComponent("active.json"))
            let foreign = CoreController(binary: binary, expectedDigest: CoreController.sourceDigest, root: foreignRoot, fixtureData: bytes)
            let unowned = await call(foreign.start)
            record("unknown_identity_preserved", unowned.errorCode == "ownership_unverified" && (try? Data(contentsOf: foreignRoot.appendingPathComponent("active.json"))) == foreignMarker, unowned)
            _ = await call(foreign.stop)

            let fd = socket(AF_INET, SOCK_STREAM, 0)
            if fd >= 0 {
                _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
                var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                address.sin_family = sa_family_t(AF_INET); address.sin_addr.s_addr = inet_addr("127.0.0.1")
                let bound = withUnsafePointer(to: &address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
                }
                var length = socklen_t(MemoryLayout<sockaddr_in>.size)
                _ = withUnsafeMutablePointer(to: &address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
                }
                if bound == 0 && listen(fd, 1) == 0 {
                    let occupiedPort = Int(UInt16(bigEndian: address.sin_port))
                    let conflict = CoreController(binary: binary, expectedDigest: CoreController.sourceDigest,
                        root: root.appendingPathComponent("conflict"), fixtureData: bytes, portAllocator: { occupiedPort })
                    let refused = await call(conflict.start)
                    record("occupied_listener_not_taken_over", refused.phase == .failed && fcntl(fd, F_GETFD) != -1, refused)
                    _ = await call(conflict.stop)
                } else { record("occupied_listener_not_taken_over", false) }
                close(fd)
            } else { record("occupied_listener_not_taken_over", false) }
        }
        exit(results.allSatisfy { $0["passed"] as? Bool == true } ? 0 : 1)
    }
}

private final class SnapshotBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [CoreSnapshot] = []
    var values: [CoreSnapshot] { lock.lock(); defer { lock.unlock() }; return storage }
    func append(_ value: CoreSnapshot) { lock.lock(); defer { lock.unlock() }; storage.append(value) }
}
