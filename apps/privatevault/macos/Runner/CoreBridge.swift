import Cocoa
import FlutterMacOS

final class CoreBridge: NSObject, FlutterStreamHandler {
    private var controller: CoreController?
    private var sink: FlutterEventSink?
    private let methods: FlutterMethodChannel
    private let events: FlutterEventChannel

    init(messenger: FlutterBinaryMessenger) {
        methods = FlutterMethodChannel(name: "dev.privatevault.w01/core", binaryMessenger: messenger)
        events = FlutterEventChannel(name: "dev.privatevault.w01/core_events", binaryMessenger: messenger)
        super.init()
        umask(0o077)
        do {
            let bundle = Bundle.main
            guard let resources = bundle.resourceURL,
                  let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: resources.appendingPathComponent("core_manifest.json"))) as? [String: String],
                  manifest["version"] == CoreController.version,
                  manifest["source_sha256"] == CoreController.sourceDigest,
                  let runtimeDigest = manifest["runtime_sha256"], runtimeDigest.count == 64,
                  let supervisorDigest = manifest["supervisor_sha256"], supervisorDigest.count == 64 else { throw CoreFailure.missingCore }
            let fixture = try Data(contentsOf: resources.appendingPathComponent("w01_sample.png"))
            guard CoreController.digest(fixture) == manifest["fixture_sha256"] else { throw CoreFailure.fixture }
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            controller = CoreController(binary: bundle.bundleURL.appendingPathComponent("Contents/Helpers/openlist"),
                                        expectedDigest: runtimeDigest, root: support.appendingPathComponent("PrivateVault-W01"), fixtureData: fixture,
                                        supervisor: bundle.bundleURL.appendingPathComponent("Contents/Helpers/core_supervisor"), supervisorDigest: supervisorDigest)
            controller?.onSnapshot = { [weak self] snapshot in
                DispatchQueue.main.async { self?.sink?(snapshot.dictionary()) }
            }
        } catch {
            // Resource or environment errors never forward raw paths, URLs or exceptions.
            controller = nil
        }
        methods.setMethodCallHandler { [weak self] call, result in
            guard let host = self?.controller else {
                result(CoreSnapshot(phase: .failed, message: "缺少完整的开发版服务文件，请重新准备。", errorCode: "missing_core").dictionary())
                return
            }
            let reply: (CoreSnapshot) -> Void = { snapshot in DispatchQueue.main.async { result(snapshot.dictionary()) } }
            switch call.method {
            case "snapshot": result(host.snapshot().dictionary())
            case "start": host.start(completion: reply)
            case "stop": host.stop(completion: reply)
            case "read_fixture": host.readFixture(completion: reply)
            default: result(FlutterMethodNotImplemented)
            }
        }
        events.setStreamHandler(self)
    }

    func stopForTermination(_ completion: @escaping () -> Void) {
        guard let controller else { completion(); return }
        controller.stop { _ in DispatchQueue.main.async(execute: completion) }
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        if let controller { events(controller.snapshot().dictionary()) }
        return nil
    }
    func onCancel(withArguments arguments: Any?) -> FlutterError? { sink = nil; return nil }
}
