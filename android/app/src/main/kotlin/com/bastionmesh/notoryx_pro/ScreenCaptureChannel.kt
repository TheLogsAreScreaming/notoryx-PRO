package com.bastionmesh.notoryx_pro

import android.app.Activity
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * "notoryx/screen_capture": setBlocked(true) sets FLAG_SECURE on the window,
 * so screenshots and screen recordings come out black and the app is blank
 * in Recents. setBlocked(false) clears it. Used while SARNEG screens show.
 */
object ScreenCaptureChannel {
    fun register(activity: Activity, messenger: BinaryMessenger) {
        MethodChannel(messenger, "notoryx/screen_capture").setMethodCallHandler { call, result ->
            if (call.method != "setBlocked") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val blocked = call.arguments as? Boolean
            if (blocked == null) {
                result.error("args", "setBlocked needs true or false", null)
                return@setMethodCallHandler
            }
            activity.runOnUiThread {
                if (blocked) {
                    activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                } else {
                    activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }
                result.success(null)
            }
        }
    }
}
