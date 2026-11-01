package dev.privatevault.w01

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var bridge: CoreHostBridge? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bridge = CoreHostBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }
    override fun onStart() { super.onStart(); bridge?.setForeground(true) }
    override fun onStop() { bridge?.setForeground(false); super.onStop() }
    override fun onDestroy() { bridge?.close(); bridge = null; super.onDestroy() }
}
