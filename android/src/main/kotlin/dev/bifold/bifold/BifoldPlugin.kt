package dev.bifold.bifold

import android.app.Activity
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Surface
import android.view.View
import androidx.core.util.Consumer
import androidx.window.core.ExperimentalWindowApi
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
  private lateinit var rearDisplayChannel: EventChannel

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
  private var rearDisplay: RearDisplay? = null
  private var rearDisplaySink: EventChannel.EventSink? = null

  private var sink: EventChannel.EventSink? = null
  private var lastPayload: Map<String, Any?>? = null

  /**
   * The capability payload that went with [lastPayload].
   *
   * Capabilities resolve on their own schedule -- window area information in
   * particular arrives well after layout -- and on a device sitting still the
   * fold payload does not change when they do. Deduplicating on the fold
   * payload alone would swallow that update, and Dart's capability stream,
   * which rides on the fold stream, would never learn about it.
   */
  private var lastCapabilities: Map<String, Any?>? = null

  private val mainHandler = Handler(Looper.getMainLooper())

  /// Runs work on the main thread, immediately when already there.
  ///
  /// Allocated one Handler per dispatch before, and always posted -- so every
  /// callback cost an allocation and a frame of latency even when it was
  /// already on the right thread. androidx wraps this in
  /// `executor.asCoroutineDispatcher()`, so it is on a warm path.
  private val mainExecutor = Executor { command ->
    if (Looper.myLooper() == mainHandler.looper) {
      command.run()
    } else {
      mainHandler.post(command)
    }
  }

  private val layoutListener = Consumer<WindowLayoutInfo> { info ->
    reader?.update(info)
    capabilities?.observeFolds(
      info.displayFeatures.filterIsInstance<FoldingFeature>(),
      displayRotation(),
    )
    emit()
  }

  private val areaListener = Consumer<List<WindowAreaInfo>> { areas ->
    capabilities?.observeWindowAreas(areas)
    rearDisplay?.observe(areas)
    emit()
  }

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    reader = FoldReader(binding.applicationContext)
    capabilities = CapabilityReader(binding.applicationContext)
    // The hinge sensor is read through a SensorManager, which needs a Context
    // and not an Activity. Building it here rather than in bind() matters for
    // correctness, not tidiness: while it was activity-scoped, any capability
    // query before the first onAttachedToActivity found it null and reported
    // `unsupported` with an authoritative source -- a false "this device has
    // no hinge sensor" on a foldable -- and every fold, being a configuration
    // change, unregistered the listener and pushed a null angle mid-gesture.
    hinge = HingeReader(binding.applicationContext) { radians ->
      reader?.update(radians)
      emit()
    }
    // A rear-display session outlives the activity, and RearDisplay takes the
    // activity per call rather than holding one, so this is engine-scoped too.
    rearDisplay = RearDisplay(
      WindowAreaController.getOrCreate(),
      mainExecutor,
      ::emitRearDisplay,
    )
    methodChannel = MethodChannel(binding.binaryMessenger, "dev.bifold/methods")
    methodChannel.setMethodCallHandler(this)
    eventChannel = EventChannel(binding.binaryMessenger, "dev.bifold/fold_info")
    eventChannel.setStreamHandler(this)
    rearDisplayChannel =
      EventChannel(binding.binaryMessenger, "dev.bifold/rear_display")
    rearDisplayChannel.setStreamHandler(
      object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
          rearDisplaySink = events
          emitRearDisplay()
        }

        override fun onCancel(arguments: Any?) {
          rearDisplaySink = null
        }
      },
    )
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    // Final teardown. This used to leave the sensor listener registered, the
    // decor-view layout listener attached and the window-area coroutine job
    // alive, which with two engines on one activity kept the plugin -- and
    // through it the Activity -- reachable from a system service.
    stopListening()
    methodChannel.setMethodCallHandler(null)
    eventChannel.setStreamHandler(null)
    rearDisplayChannel.setStreamHandler(null)
    sink = null
    rearDisplaySink = null
    rearDisplay?.end()
    rearDisplay = null
    hinge = null
    reader = null
    capabilities = null
    activity = null
    tracker = null
    areaController = null
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
    // The activity is going away for good rather than being recreated, so
    // anything scoped to the app being on screen goes with it.
    rearDisplay?.end()
    rearDisplay = null
  }

  private fun bind(activity: Activity) {
    this.activity = activity
    reader?.attach(activity)
    tracker = WindowInfoTrackerCallbackAdapter(WindowInfoTracker.getOrCreate(activity))
    areaController = WindowAreaControllerCallbackAdapter(WindowAreaController.getOrCreate())
    if (sink != null) {
      startObserving()
    }
  }

  /**
   * Releases what is bound to the activity.
   *
   * Deliberately does NOT end a rear-display session. Folding is a
   * configuration change, so this runs in the middle of the one gesture the
   * package exists to report; ending the session here closed the presentation
   * as the device folded, and `transferActivityToWindowArea` causes a
   * configuration change by design, so transfer could never complete at all.
   * A session outlives the activity and is ended in [onDetachedFromActivity]
   * and [onDetachedFromEngine] instead.
   */
  private fun unbind() {
    stopObserving()
    reader?.detach()
    activity = null
    tracker = null
    areaController = null
  }

  /**
   * Starts the observation that needs an activity.
   *
   * The hinge sensor is deliberately not started here: it is engine-scoped and
   * follows whether anyone is listening, not which activity is current. See
   * [startListening].
   */
  private fun startObserving() {
    val activity = activity ?: return
    tracker?.addWindowLayoutInfoListener(activity, mainExecutor, layoutListener)
    activity.window?.decorView?.addOnLayoutChangeListener(layoutPassListener)
    areaController?.addWindowAreaInfoListListener(mainExecutor, areaListener)
  }

  /**
   * Stops the activity-scoped observation only.
   *
   * This runs on every configuration change, and folding is a configuration
   * change. Unregistering the hinge sensor here cleared the angle to null in
   * the middle of the fold gesture -- the one moment an app reading the angle
   * cares about -- so the sensor is left to [stopListening].
   */
  private fun stopObserving() {
    tracker?.removeWindowLayoutInfoListener(layoutListener)
    activity?.window?.decorView?.removeOnLayoutChangeListener(layoutPassListener)
    areaController?.removeWindowAreaInfoListListener(areaListener)
  }

  /** Begins everything that follows a Dart listener rather than an activity. */
  private fun startListening() {
    startObserving()
    hinge?.start()
  }

  /** Ends it. Clearing the angle here is correct: nothing is reading it. */
  private fun stopListening() {
    stopObserving()
    hinge?.stop()
  }

  // --- One-shot queries ---------------------------------------------------

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "getFoldInfo" -> result.success(currentPayload())
      "getCapabilities" -> result.success(currentCapabilities())
      "rearDisplayStatus" -> result.success(rearDisplay?.status() ?: unsupportedRearDisplay())
      "presentOnRearDisplay" -> {
        val activity = activity
        val entrypoint = call.argument<String>("entrypoint")
        if (activity == null || entrypoint == null) {
          result.success(false)
        } else {
          result.success(
            rearDisplay?.present(
              activity,
              entrypoint,
              call.argument<String>("libraryUri"),
            ) == true,
          )
        }
      }
      "transferToRearDisplay" -> {
        val activity = activity
        result.success(
          if (activity == null) false else rearDisplay?.transfer(activity) == true,
        )
      }
      "endRearDisplay" -> {
        rearDisplay?.end()
        result.success(null)
      }
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
    reader?.payload(
      hingeSensorPresent = hinge?.isPresent == true,
      capabilityRevision = capabilities?.revision ?: 0,
    )
      ?: FoldReader.unsupportedPayload()

  private fun currentCapabilities(): Map<String, Any?> =
    capabilities?.payload(hingeSensorPresent = hinge?.isPresent == true)
      ?: mapOf(
        "version" to BIFOLD_PAYLOAD_VERSION,
        "platform" to "android",
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

  private fun unsupportedRearDisplay(): Map<String, String> =
    mapOf("presentation" to "unsupported", "transfer" to "unsupported")

  private fun emitRearDisplay() {
    rearDisplaySink?.success(rearDisplay?.status() ?: unsupportedRearDisplay())
  }

  private fun describeNativeApi(): String {
    val hinge = hinge
    return buildString {
      appendLine("bifold on Android")
      appendLine("  android.os.Build.VERSION.SDK_INT: ${android.os.Build.VERSION.SDK_INT}")
      appendLine("  model: ${android.os.Build.MODEL}")
      // Read from the build rather than typed in: a hardcoded version here
      // would keep reporting 1.2.0 after the dependency moved, in the one
      // string whose whole purpose is to be accurate in a bug report.
      appendLine("  androidx.window: ${BuildConfig.WINDOW_VERSION}")
      appendLine("  hinge angle sensor present: ${hinge?.isPresent == true}")
      appendLine("  activity attached: ${activity != null}")
    }
  }

  // --- The stream ---------------------------------------------------------

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    sink = events
    startListening()
    // Emit at once so the first frame has something rather than waiting for
    // the first layout callback, which may never come on a device with no
    // fold to report.
    emit()
  }

  override fun onCancel(arguments: Any?) {
    stopListening()
    sink = null
    lastPayload = null
    lastCapabilities = null
  }

  /**
   * Sends the current reading, unless nothing at all has changed.
   *
   * "Nothing" means neither the fold state nor the capabilities: a capability
   * settling is a reason to emit even when the device has not moved, because
   * that is how the change reaches Dart.
   */
  private fun emit() {
    val sink = sink ?: return
    val payload = currentPayload()
    val capabilityPayload = currentCapabilities()
    if (payload == lastPayload && capabilityPayload == lastCapabilities) return
    lastPayload = payload
    lastCapabilities = capabilityPayload
    sink.success(payload)
  }
}
