package com.bastionmesh.notoryx_pro

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        HeadingChannel.register(this, flutterEngine.dartExecutor.binaryMessenger)
        ScreenCaptureChannel.register(this, flutterEngine.dartExecutor.binaryMessenger)
        SecretClipboard.register(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onResume() {
        super.onResume()
        // Backstop for the scheduled clipboard clear (see SecretClipboard).
        SecretClipboard.clearIfDue(this)
    }
}
