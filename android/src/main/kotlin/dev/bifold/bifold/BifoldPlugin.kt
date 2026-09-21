package dev.bifold.bifold

import android.app.Activity
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Surface
import android.view.View
import androidx.core.util.Consumer
import androidx.window.area.WindowAreaController
import androidx.window.area.WindowAreaInfo
import androidx.window.java.area.WindowAreaControllerCallbackAdapter
import androidx.window.java.layout.WindowInfoTrackerCallbackAdapter
import androidx.window.layout.FoldingFeature
import androidx.window.layout.WindowInfoTracker
import androidx.window.layout.WindowLayoutInfo
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor

/**
 * The Android side of `bifold`.
 *
 * Channel names and payload shape match the iOS plugin exactly, so Dart
 * decodes one model for both platforms and nothing above the channel has to
 * know which one it is talking to.
 *
 * Everything here degrades rather than fails. With no activity attached, no
 * fold and no hinge sensor, this still answers, with the same "no fold"
 * payload a non-foldable device produces.
 */
class BifoldPlugin :
  FlutterPlugin,
  ActivityAware,
  MethodChannel.MethodCallHandler,
  EventChannel.StreamHandler {

  private lateinit var methodChannel: MethodChannel
  private lateinit var eventChannel: EventChannel

  private var activity: Activity? = null
  private var tracker: WindowInfoTrackerCallbackAdapter? = null
  private var hinge: HingeReader? = null

  /**
   * Outlives the activity on purpose.
   *
   * A fold recreates the activity, and a reader rebuilt with it would forget
   * that it had ever seen a fold at the exact moment one was happening.
   */
  private var reader: FoldReader? = null

  /**
   * Also outlives the activity: capabilities are about the device, and a fold
   * gesture must never look like the device losing one.
   */
  private var capabilities: CapabilityReader? = null

  private var areaController: WindowAreaControllerCallbackAdapter? = null

  private var sink: EventChannel.EventSink? = null
  private var lastPayload: Map<String, Any?>? = null

  private val mainExecutor = Executor { Handler(Looper.getMainLooper()).post(it) }

  private val layoutListener = Consumer<WindowLayoutInfo> { info ->
    reader?.update(info)
    capabilities?.observeFolds(
      info.displayFeatures.filterIsInstance<FoldingFeature>(),
    )
    emit()
  }

  private val areaListener = Consumer<List<WindowAreaInfo>> { areas ->
    capabilities?.observeWindowAreas(areas)
    emit()
  }

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    reader = FoldReader(binding.applicationContext)
    capabilities = CapabilityReader(binding.applicationContext)
    methodChannel = MethodChannel(binding.binaryMessenger, "dev.bifold/methods")
    methodChannel.setMethodCallHandler(this)
    eventChannel = EventChannel(binding.binaryMessenger, "dev.bifold/fold_info")
    eventChannel.setStreamHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    methodChannel.setMethodCallHandler(null)
    eventChannel.setStreamHandler(null)
    reader = null
    capabilities = null
  }

  /**
   * Re-reads state when the window itself changes size.
   *
   * The window layout callback fires the moment a folding feature appears or
   * goes, which is *before* the window has finished resizing around it. Taken
   * on its own it freezes the old display's measurements into the payload and
   * nothing ever corrects them, because no further fold event is coming. A
   * layout pass on the decor view is the signal that the new bounds are real,
   * and it covers multi-window resizing too.
   */
  private val layoutPassListener = View.OnLayoutChangeListener {
      _, _, _, _, _, _, _, _, _ ->
    emit()
  }

  // --- Activity lifecycle -------------------------------------------------
  //
  // Folding a device is a configuration change, and the activity is recreated
  // partway through it. Observation is bound to the activity and so has to be
  // rebuilt here; the sink is not, and deliberately survives, so a fold does
  // not silently end the Dart stream halfway through the gesture.

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    bind(binding.activity)
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    bind(binding.activity)
  }

  override fun onDetachedFromActivityForConfigChanges() {
    unbind()
  }

  override fun onDetachedFromActivity() {
    unbind()
  }

  private fun bind(activity: Activity) {
    this.activity = activity
    reader?.attach(activity)
    tracker = WindowInfoTrackerCallbackAdapter(WindowInfoTracker.getOrCreate(activity))
    areaController = WindowAreaControllerCallbackAdapter(WindowAreaController.getOrCreate())
    hinge = HingeReader(activity) { radians ->
      reader?.update(radians)
      emit()
    }
    if (sink != null) {
      startObserving()
    }
  }

  private fun unbind() {
    stopObserving()
    reader?.detach()
    activity = null
    tracker = null
    areaController = null
    hinge = null
  }

  private fun startObserving() {
    val activity = activity ?: return
    tracker?.addWindowLayoutInfoListener(activity, mainExecutor, layoutListener)
    activity.window?.decorView?.addOnLayoutChangeListener(layoutPassListener)
    areaController?.addWindowAreaInfoListListener(mainExecutor, areaListener)
    hinge?.start()
  }

  private fun stopObserving() {
    tracker?.removeWindowLayoutInfoListener(layoutListener)
    activity?.window?.decorView?.removeOnLayoutChangeListener(layoutPassListener)
    areaController?.removeWindowAreaInfoListListener(areaListener)
    hinge?.stop()
  }

  // --- One-shot queries ---------------------------------------------------

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "getFoldInfo" -> result.success(currentPayload())
      "getCapabilities" -> result.success(currentCapabilities())
      "debugDescribeNativeApi" -> result.success(describeNativeApi())
      // The capture accessory is iOS-only today. Answering rather than
      // failing keeps BifoldCaptureAccessory usable from shared code.
      "captureAccessorySupported" -> result.success(false)
      "isCaptureAccessoryAvailable" -> result.success(false)
      "registerCaptureAccessory" -> result.success(false)
      "unregisterCaptureAccessory", "setCaptureAccessoryEnabled" -> result.success(null)
      else -> result.notImplemented()
    }
  }

  private fun currentPayload(): Map<String, Any?> =
    reader?.payload(hingeSensorPresent = hinge?.isPresent == true)
      ?: FoldReader.unsupportedPayload()

  private fun currentCapabilities(): Map<String, Any?> =
    capabilities?.payload(
      hingeSensorPresent = hinge?.isPresent == true,
      rotation = displayRotation(),
    )
      ?: mapOf(
        "isResolved" to false,
        "formFactor" to "unknown",
        "rearDisplayModes" to emptyList<String>(),
        "features" to emptyMap<String, Any?>(),
      )

  /**
   * How the screen is currently turned, so a hinge orientation can be read as
   * a property of the device rather than of the rotation.
   */
  @Suppress("DEPRECATION")
  private fun displayRotation(): Int {
    val activity = activity ?: return Surface.ROTATION_0
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      activity.display?.rotation ?: Surface.ROTATION_0
    } else {
      activity.windowManager.defaultDisplay.rotation
    }
  }

  private fun describeNativeApi(): String {
    val hinge = hinge
    return buildString {
      appendLine("bifold on Android")
      appendLine("  android.os.Build.VERSION.SDK_INT: ${android.os.Build.VERSION.SDK_INT}")
      appendLine("  model: ${android.os.Build.MODEL}")
      appendLine("  androidx.window: 1.2.0")
      appendLine("  hinge angle sensor present: ${hinge?.isPresent == true}")
      appendLine("  activity attached: ${activity != null}")
    }
  }

  // --- The stream ---------------------------------------------------------

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    sink = events
    startObserving()
    // Emit at once so the first frame has something rather than waiting for
    // the first layout callback, which may never come on a device with no
    // fold to report.
    emit()
  }

  override fun onCancel(arguments: Any?) {
    stopObserving()
    sink = null
    lastPayload = null
  }

  /** Sends the current reading, unless it is identical to the last one sent. */
  private fun emit() {
    val sink = sink ?: return
    val payload = currentPayload()
    if (payload == lastPayload) return
    lastPayload = payload
    sink.success(payload)
  }
}
