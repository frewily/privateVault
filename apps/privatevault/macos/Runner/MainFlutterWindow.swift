import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
    private(set) var coreBridge: CoreBridge?
    override func awakeFromNib() {
        let controller = FlutterViewController()
        contentViewController = controller
        setContentSize(NSSize(width: 1000, height: 700))
        minSize = NSSize(width: 660, height: 520)
        title = "PrivateVault W01"
        center()
        RegisterGeneratedPlugins(registry: controller)
        coreBridge = CoreBridge(messenger: controller.engine.binaryMessenger)
        (NSApplication.shared.delegate as? AppDelegate)?.coreBridge = coreBridge
        super.awakeFromNib()
    }
}
