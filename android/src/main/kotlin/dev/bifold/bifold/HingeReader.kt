package dev.bifold.bifold

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build

/**
 * Reads the hinge angle, when the device has a hinge angle sensor to read.
 *
 * The sensor reports degrees. Dart's `FoldInfo.hingeAngle` is documented in
 * radians, so the conversion happens here rather than in Dart, keeping the
 * channel payload in the units the published API promises.
 *
 * `Sensor.TYPE_HINGE_ANGLE` (value 36) arrived in API 30, verified against
 * `android.jar` for API 36. Below that the sensor is simply absent and the
 * angle stays null, which is a documented state rather than a failure.
 */
internal class HingeReader(
  context: Context,
  private val onAngle: (Double?) -> Unit,
) : SensorEventListener {

  private val manager = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager

  private val sensor: Sensor? =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      manager?.getDefaultSensor(Sensor.TYPE_HINGE_ANGLE)
    } else {
      null
    }

  /**
   * Whether this device exposes a hinge angle sensor at all.
   *
   * Presence is not delivery: a sensor can be listed and never report. That is
   * why this only describes the source, and the angle itself stays nullable.
   */
  val isPresent: Boolean get() = sensor != null

  private var listening = false

  fun start() {
    val sensor = sensor ?: return
    if (listening) return
    listening = manager?.registerListener(
      this,
      sensor,
      SensorManager.SENSOR_DELAY_NORMAL,
    ) == true
  }

  fun stop() {
    if (!listening) return
    manager?.unregisterListener(this)
    listening = false
    // An unregistered sensor has no current reading. Leaving the last one in
    // place is how a stale angle outlives the thing that produced it.
    onAngle(null)
  }

  override fun onSensorChanged(event: SensorEvent?) {
    val degrees = event?.values?.firstOrNull() ?: return
    onAngle(Math.toRadians(degrees.toDouble()))
  }

  override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
}
