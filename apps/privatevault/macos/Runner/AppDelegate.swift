import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
    var coreBridge: CoreBridge?
    private var terminating = false

    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let bridge = coreBridge ?? sender.windows.compactMap { ($0 as? MainFlutterWindow)?.coreBridge }.first
        guard let coreBridge = bridge else { return .terminateNow }
        guard !terminating else { return .terminateLater }
        terminating = true
        coreBridge.stopForTermination { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}
