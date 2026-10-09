package dev.bifold.bifold

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.display.DisplayManager
import android.os.Build
import android.view.Surface
import androidx.window.core.ExperimentalWindowApi
import androidx.window.area.WindowAreaCapability
import androidx.window.area.WindowAreaInfo
import androidx.window.layout.FoldingFeature

/**
 * Answers what this device *can* do, as opposed to what it is doing.
 *
 * The rules this has to respect, and which the Dart resolver enforces across
 * reports, are worth restating because they shape everything below:
 *
 * * Only an authoritative static query may report `unsupported`. Never having
 *   observed something is not evidence it is absent.
 * * An observation may only ever move a capability up to `supported`.
 * * Anything else is `unknown`, which is a real answer and not a failure.
 */
// Every androidx.window.area symbol is @ExperimentalWindowApi. The
// annotation is only RequiresOptIn.Level.WARNING, so this compiled without
// saying so anywhere -- which hid the fact that the whole rear-display
// feature rests on an API that can change without a major version.
@OptIn(ExperimentalWindowApi::class)
internal class CapabilityReader(context: Context) {

  private val appContext = context.applicationContext

  /**
   * The static signal for a hinge, verified to answer on a closed device.
   *
   * `PackageManager.FEATURE_SENSOR_HINGE_ANGLE` is authoritative in the
   * positive: a device declaring it has a hinge. It is *not* authoritative in
   * the negative, because a foldable could ship without a hinge angle sensor,
   * which is why its absence yields `unknown` rather than `unsupported`.
   */
  private val declaresHinge: Boolean =
    appContext.packageManager.hasSystemFeature(PackageManager.FEATURE_SENSOR_HINGE_ANGLE)

  /// The sticky observations and the revision rule, extracted so they can be
  /// unit-tested on the JVM -- this class needs a Context and so cannot be.
  private val observations = CapabilityObservations()

  /// See [CapabilityObservations.revision].
  val revision: Int get() = observations.revision

  private val sawFold: Boolean get() = observations.sawFold
  private val sawHalfOpened: Boolean get() = observations.sawHalfOpened
  private val sawSeparating: Boolean get() = observations.sawSeparating
  private val sawOcclusion: Boolean get() = observations.sawOcclusion
  private val sawWindowAreaReport: Boolean get() = observations.sawWindowAreaReport

  private var windowAreas: List<WindowAreaInfo> = emptyList()

  /** Folds an observation in. Observations only ever add. */
  fun observeFolds(folds: List<FoldingFeature>, rotation: Int) =
    observations.observeFolds(folds, rotation)

  fun observeWindowAreas(areas: List<WindowAreaInfo>) {
    windowAreas = areas
    // The modes are the capability-relevant projection of the report; the
    // objects themselves are new on every emission.
    observations.observeWindowAreas(rearDisplayModes())
  }

  fun payload(hingeSensorPresent: Boolean): Map<String, Any?> = mapOf(
    "version" to BIFOLD_PAYLOAD_VERSION,
    // Brief decision 4: platform belongs in `raw` and the diagnostic report,
    // never as a typed getter on BifoldCapabilities.
    "platform" to "android",
    "isResolved" to true,
    "formFactor" to formFactor(),
    "rearDisplayModes" to rearDisplayModes(),
    "features" to mapOf(
      "fold" to fold(),
      "hingeAngle" to hingeAngle(hingeSensorPresent),
      "halfOpenedPosture" to halfOpenedPosture(),
      "rearDisplay" to rearDisplay(),
      "coverDisplay" to coverDisplay(),
      "reservedRegions" to reservedRegions(),
      "separatingFold" to separatingFold(),
      "foldOcclusion" to foldOcclusion(),
    ),
  )

  private fun evidence(status: String, source: String) =
    mapOf("status" to status, "source" to source)

  private fun fold(): Map<String, Any?> = when {
    declaresHinge ->
      evidence("supported", "android.pm.FEATURE_SENSOR_HINGE_ANGLE")
    sawFold -> evidence("supported", "androidx.window.FoldingFeature")
    // No static negative exists. A device can fold and declare nothing.
    else -> evidence("unknown", "android.no_static_signal")
  }

  private fun hingeAngle(present: Boolean): Map<String, Any?> = when {
    Build.VERSION.SDK_INT < Build.VERSION_CODES.R ->
      evidence("unsupported", "android.api_level_below_30")
    present -> evidence("supported", "android.sensor.TYPE_HINGE_ANGLE")
    // SensorManager enumerates every sensor, so absence here is authoritative.
    else -> evidence("unsupported", "android.sensor.TYPE_HINGE_ANGLE_absent")
  }

  /**
   * The capability that genuinely needs three states.
   *
   * Android exposes no static query for "can this device report a half-opened
   * posture". Observing one proves it; never having observed one proves
   * nothing, which is exactly the case a boolean cannot express.
   */
  private fun halfOpenedPosture(): Map<String, Any?> = when {
    sawHalfOpened -> evidence("supported", "androidx.window.State.HALF_OPENED")
    else -> evidence("unknown", "android.not_yet_observed")
  }

  private fun rearDisplay(): Map<String, Any?> {
    if (windowAreas.isEmpty()) {
      return if (sawWindowAreaReport) {
        evidence("unsupported", "androidx.window.area.no_window_areas")
      } else {
        evidence("unknown", "androidx.window.area.not_yet_reported")
      }
    }
    val supported = windowAreas.any { info ->
      OPERATIONS.any { operation ->
        info.getCapability(operation).status !=
          WindowAreaCapability.Status.WINDOW_AREA_STATUS_UNSUPPORTED
      }
    }
    return if (supported) {
      evidence("supported", "androidx.window.area.WindowAreaCapability")
    } else {
      evidence("unsupported", "androidx.window.area.WINDOW_AREA_STATUS_UNSUPPORTED")
    }
  }

  /**
   * Whether the modes are available *at all*, not whether they can run now.
   *
   * Status carries availability — unavailable, available, active — and that is
   * current state, not capability. Only `unsupported` belongs here.
   */
  private fun rearDisplayModes(): List<String> {
    val modes = mutableListOf<String>()
    for (info in windowAreas) {
      if (info.getCapability(PRESENT).status !=
        WindowAreaCapability.Status.WINDOW_AREA_STATUS_UNSUPPORTED
      ) {
        modes.add("presentation")
      }
      if (info.getCapability(TRANSFER).status !=
        WindowAreaCapability.Status.WINDOW_AREA_STATUS_UNSUPPORTED
      ) {
        modes.add("transfer")
      }
    }
    return modes.distinct()
  }

  /**
   * Honestly unknown on Android, in most cases permanently.
   *
   * More than one display is necessary but nowhere near sufficient: whether an
   * app may actually *run* on a cover display is OEM policy, with no public
   * query behind it. A second display moves this no further than "there is
   * something there", so it stays `unknown` and never claims support.
   */
  private fun coverDisplay(): Map<String, Any?> {
    // Deliberately `unknown` either way, and the branch exists only to say
    // *why* in the diagnostic report. Android has no query for "can an app
    // run on the cover display while this device is shut": DisplayManager
    // enumerates displays, but a second display may be an external monitor,
    // a virtual display or a cast target, and whether the system will launch
    // this app onto it is device policy rather than anything an app can ask.
    // Reporting `supported` from a display count would be a guess, and
    // `unsupported` would be a stronger claim than the evidence allows --
    // so this stays the honest third answer.
    val displays = (appContext.getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager)
      ?.displays?.size ?: 0
    return if (displays > 1) {
      evidence("unknown", "android.multiple_displays_but_no_policy_query")
    } else {
      evidence("unknown", "android.no_cover_display_query")
    }
  }

  private fun reservedRegions(): Map<String, Any?> = when {
    sawFold -> evidence("supported", "androidx.window.FoldingFeature.bounds")
    // A declared hinge means a fold will be reported with bounds once the
    // device is opened, so the distinction is worth keeping -- but only as a
    // different source string, because neither case is established yet. The
    // two branches used to be byte-identical, which read as unfinished.
    declaresHinge -> evidence("unknown", "android.hinge_declared_fold_unobserved")
    else -> evidence("unknown", "android.not_yet_observed")
  }

  private fun separatingFold(): Map<String, Any?> = when {
    sawSeparating -> evidence("supported", "androidx.window.isSeparating")
    else -> evidence("unknown", "android.not_yet_observed")
  }

  private fun foldOcclusion(): Map<String, Any?> = when {
    sawOcclusion -> evidence("supported", "androidx.window.OcclusionType.FULL")
    else -> evidence("unknown", "android.not_yet_observed")
  }

  private fun formFactor(): String = observations.formFactor()

  private companion object {
    val PRESENT = WindowAreaCapability.Operation.OPERATION_PRESENT_ON_AREA
    val TRANSFER = WindowAreaCapability.Operation.OPERATION_TRANSFER_ACTIVITY_TO_AREA
    val OPERATIONS = listOf(PRESENT, TRANSFER)
  }
}
