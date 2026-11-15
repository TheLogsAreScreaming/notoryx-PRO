package com.bastionmesh.notoryx_pro

import android.app.Activity
import android.content.Context
import android.hardware.GeomagneticField
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.SystemClock
import android.view.Surface
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * The phone's compass heading for the compass screen.
 *
 * "notoryx/heading" streams {heading: degrees from magnetic north,
 * accuracy: SensorManager accuracy 0-3} about 20 times a second from the
 * rotation-vector sensor, adjusted for how the screen is turned.
 * "notoryx/declination" turns a position into the magnetic declination,
 * so Dart can correct to true north.
 */
object HeadingChannel {
    fun register(activity: Activity, messenger: BinaryMessenger) {
        val sensors = activity.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        EventChannel(messenger, "notoryx/heading").setStreamHandler(Stream(activity, sensors))
        MethodChannel(messenger, "notoryx/declination").setMethodCallHandler { call, result ->
            if (call.method != "declination") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val lat = call.argument<Double>("lat")
            val lon = call.argument<Double>("lon")
            if (lat == null || lon == null) {
                result.error("args", "lat and lon are needed", null)
                return@setMethodCallHandler
            }
            val alt = (call.argument<Double>("alt") ?: 0.0).toFloat()
            val field = GeomagneticField(
                lat.toFloat(), lon.toFloat(), alt, System.currentTimeMillis()
            )
            result.success(field.declination.toDouble())
        }
    }

    private class Stream(
        private val activity: Activity,
        private val sensors: SensorManager,
    ) : EventChannel.StreamHandler, SensorEventListener {
        private var sink: EventChannel.EventSink? = null
        private var accuracy = SensorManager.SENSOR_STATUS_UNRELIABLE
        private var lastSent = 0L
        private val rotation = FloatArray(9)
        private val remapped = FloatArray(9)
        private val angles = FloatArray(3)

        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            val sensor = sensors.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
            if (sensor == null) {
                events.error("unavailable", "No compass on this device", null)
                return
            }
            sink = events
            sensors.registerListener(this, sensor, 50_000)
        }

        override fun onCancel(arguments: Any?) {
            sensors.unregisterListener(this)
            sink = null
        }

        override fun onAccuracyChanged(sensor: Sensor?, value: Int) {
            accuracy = value
        }

        override fun onSensorChanged(event: SensorEvent) {
            val now = SystemClock.elapsedRealtime()
            if (now - lastSent < 50) return
            lastSent = now
            SensorManager.getRotationMatrixFromVector(rotation, event.values)
            val (x, y) = when (displayRotation()) {
                Surface.ROTATION_90 -> SensorManager.AXIS_Y to SensorManager.AXIS_MINUS_X
                Surface.ROTATION_180 -> SensorManager.AXIS_MINUS_X to SensorManager.AXIS_MINUS_Y
                Surface.ROTATION_270 -> SensorManager.AXIS_MINUS_Y to SensorManager.AXIS_X
                else -> SensorManager.AXIS_X to SensorManager.AXIS_Y
            }
            SensorManager.remapCoordinateSystem(rotation, x, y, remapped)
            SensorManager.getOrientation(remapped, angles)
            val degrees = (Math.toDegrees(angles[0].toDouble()) + 360.0) % 360.0
            sink?.success(mapOf("heading" to degrees, "accuracy" to accuracy))
        }

        @Suppress("DEPRECATION")
        private fun displayRotation(): Int =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                activity.display?.rotation ?: Surface.ROTATION_0
            } else {
                activity.windowManager.defaultDisplay.rotation
            }
    }
}
