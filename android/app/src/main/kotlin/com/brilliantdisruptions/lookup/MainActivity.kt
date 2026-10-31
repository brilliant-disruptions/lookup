package com.brilliantdisruptions.lookup

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    // Ambient light for night vision's red strength (lib/services/ambient_light.dart).
    EventChannel(flutterEngine.dartExecutor.binaryMessenger, "lookup/ambient_light")
      .setStreamHandler(AmbientLightHandler(getSystemService(Context.SENSOR_SERVICE) as SensorManager))
  }
}

/// Lux from the light sensor while Dart listens. Phones without one send
/// nothing, and night vision stays full red.
private class AmbientLightHandler(private val sensors: SensorManager) : EventChannel.StreamHandler, SensorEventListener {
  private var sink: EventChannel.EventSink? = null

  override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
    val light = sensors.getDefaultSensor(Sensor.TYPE_LIGHT) ?: return
    sink = events
    sensors.registerListener(this, light, SensorManager.SENSOR_DELAY_NORMAL)
  }

  override fun onCancel(arguments: Any?) {
    sensors.unregisterListener(this)
    sink = null
  }

  override fun onSensorChanged(event: SensorEvent) {
    sink?.success(mapOf("lux" to event.values[0].toDouble()))
  }

  override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {}
}
