package com.muhammad.gtaremote

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/// GTA Remote ki MainActivity.
///
/// Saara Bluetooth HID kaam [HidKeyboardManager] karta hai; ye activity
/// sirf use banati hai aur Android ke lifecycle/result callbacks use
/// forward karti hai.
class MainActivity : FlutterActivity() {

    private var hidManager: HidKeyboardManager? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        hidManager = HidKeyboardManager(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onPause() {
        // App background me jaye to manager khud saari keys chhor kar
        // unregister kar deta hai (safety).
        hidManager?.onHostPause()
        super.onPause()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        if (hidManager?.onRequestPermissionsResult(requestCode, grantResults) == true) {
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (hidManager?.onActivityResult(requestCode, resultCode) == true) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        hidManager?.dispose()
        hidManager = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
