package dev.bifold.bifold

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import androidx.window.layout.FoldingFeature
import androidx.window.layout.WindowLayoutInfo
import androidx.window.layout.WindowMetricsCalculator

/** The payload version Dart's `kBifoldPayloadVersion` expects. */
internal const val BIFOLD_PAYLOAD_VERSION = 1

/**
 * Turns Android's window and sensor state into the same channel payload the
 * iOS plugin sends.
 *
 * Dart decodes one shape for every platform, so the mapping decisions live
 * here and are documented where they are made. Each one is recorded in
 * `API_NOTES.md` with the artifact it was verified against.
 */
internal class FoldReader(context: Context) {

  /**
   * The activity currently hosting the Flutter view, or null between an
   * activity being torn down and its replacement arriving.
   *
   * Folding is a configuration change and the activity is recreated partway
   * through it, so this moves. Everything below it -- whether a fold has ever
   * been seen, the last layout, the last angle -- deliberately does not, or a
   * fold gesture would erase the very state it is producing.
   */
  private var activity: Activity? = null

  private val appContext: Context = context.applicationContext

  fun attach(activity: Activity) {
    this.activity = activity
  }

  fun detach() {
    activity = null
  }

  /**
   * Whether this device has ever reported a fold to this process.
   *
   * A closed foldable reports no folding feature at all, and `FoldingFeature`
   * has no closed state — only `FLAT` and `HALF_OPENED`, verified against
   * `window-1.2.0.aar`. So the absence of a feature proves nothing, and seeing
   * one must never be forgotten while the process lives.
   */
  private var everSawFold = false

  private var latest: WindowLayoutInfo? = null
  private var hingeRadians: Double? = null

  /**
   * The authoritative static signal for "this device has a hinge".
   *
   * `PackageManager.FEATURE_SENSOR_HINGE_ANGLE` is the string
   * `android.hardware.sensor.hinge_angle`, verified against `android.jar`. It
   * answers on a closed device, where no folding feature exists, which is the
   * case no runtime observation can cover.
   *
   * It is a sufficient signal, not a necessary one: a foldable without a hinge
   * angle sensor would report false here and still be caught by [everSawFold].
   */
  private val declaresHinge: Boolean =
    appContext.packageManager.hasSystemFeature(PackageManager.FEATURE_SENSOR_HINGE_ANGLE)

  fun update(info: WindowLayoutInfo) {
    latest = info
    if (info.displayFeatures.filterIsInstance<FoldingFeature>().isNotEmpty()) {
      everSawFold = true
    }
  }

  fun update(hingeRadians: Double?) {
    this.hingeRadians = hingeRadians
  }

  fun payload(hingeSensorPresent: Boolean): Map<String, Any?> {
    val activity = activity
    val density = (activity ?: appContext).resources.displayMetrics.density.toDouble()
    val folds = latest?.displayFeatures?.filterIsInstance<FoldingFeature>() ?: emptyList()
    val isFoldable = declaresHinge || everSawFold || hingeSensorPresent

    return mapOf(
      "version" to BIFOLD_PAYLOAD_VERSION,
      "isFoldable" to isFoldable,
      "display" to display(folds),
      "pose" to pose(folds),
      "regions" to folds.map { region(it, density) },
      "hingeAngle" to hingeRadians,
      "horizontalSizeClass" to horizontalSizeClass(activity, density),
      "verticalSizeClass" to verticalSizeClass(activity, density),
      // Android has no system vertical bar to reserve an edge for.
      "verticalBarEdge" to "unspecified",
    )
  }

  /**
   * Which display the app is on.
   *
   * A folding feature is only reported for the display that has the fold, so
   * seeing one places the app on the inner display. The converse does not
   * hold: no feature means closed, or on a cover display, or not a foldable,
   * and Android offers no documented way to tell those apart. Reporting
   * `none` there says "not determined", which is what `FoldDisplay.none`
   * means, rather than guessing.
   */
  private fun display(folds: List<FoldingFeature>): String =
    if (folds.isNotEmpty()) "inner" else "none"

  /**
   * How far the device is folded.
   *
   * `FLAT` and `HALF_OPENED` map onto the poses iOS already reports. There is
   * deliberately no mapping to `closed`: Android reports no folding feature
   * when shut, which is indistinguishable from a non-foldable device, and
   * claiming `closed` from an absence would be inventing a reading.
   */
  private fun pose(folds: List<FoldingFeature>): String {
    val fold = folds.firstOrNull() ?: return "unknown"
    return when (fold.state) {
      FoldingFeature.State.HALF_OPENED -> "partiallyOpen"
      FoldingFeature.State.FLAT -> "fullyOpen"
      else -> "unknown"
    }
  }

  /**
   * One folding feature as a reserved region.
   *
   * Bounds come back in pixels relative to the window and are divided by the
   * display density to reach the logical pixels Dart works in.
   *
   * Margins are zero. Android reports the hardware bounds with no clearance
   * around them, unlike iOS where the frame arrives with clearance already
   * built in, so here `frame` and `reservedRect` are the same rectangle. This
   * is a real difference between the platforms, not a gap in the mapping.
   *
   * `isActive` follows `isSeparating` rather than the state: a fold is worth
   * laying out around exactly when it currently divides the window, which is
   * the same thing iOS's active division means.
   */
  private fun region(fold: FoldingFeature, density: Double): Map<String, Any?> {
    val bounds = fold.bounds
    return mapOf(
      "kind" to "division",
      "left" to bounds.left / density,
      "top" to bounds.top / density,
      "right" to bounds.right / density,
      "bottom" to bounds.bottom / density,
      "marginLeft" to 0.0,
      "marginTop" to 0.0,
      "marginRight" to 0.0,
      "marginBottom" to 0.0,
      "isActive" to fold.isSeparating,
    )
  }

  /**
   * Size classes, derived rather than reported.
   *
   * UIKit hands iOS a size class outright. Android has no equivalent on the
   * activity, so these come from the current window width and height against
   * the documented Material window size class breakpoints: 600dp for width,
   * 480dp for height. Anything at or above the breakpoint is regular.
   *
   * Without this every Android device would report `unspecified`, `isRegular`
   * would always be false, and `BifoldScaffold` would render its compact
   * layout on tablets and unfolded foldables alike.
   */
  private fun horizontalSizeClass(activity: Activity?, density: Double): String {
    val bounds = windowBounds(activity) ?: return "unspecified"
    return if (bounds.width() / density < 600) "compact" else "regular"
  }

  private fun verticalSizeClass(activity: Activity?, density: Double): String {
    val bounds = windowBounds(activity) ?: return "unspecified"
    return if (bounds.height() / density < 480) "compact" else "regular"
  }

  /**
   * The current window, measured now rather than when the activity arrived.
   *
   * These bounds move under the app: folding, unfolding and multi-window all
   * resize the window without producing a new activity every time, so this is
   * read on every payload instead of being cached.
   */
  private fun windowBounds(activity: Activity?): android.graphics.Rect? =
    activity?.let {
      WindowMetricsCalculator.getOrCreate().computeCurrentWindowMetrics(it).bounds
    }

  companion object {
    /** What a platform with nothing to report sends. Mirrors iOS exactly. */
    fun unsupportedPayload(): Map<String, Any?> = mapOf(
      "version" to BIFOLD_PAYLOAD_VERSION,
      "isFoldable" to false,
      "display" to "none",
      "pose" to "unknown",
      "regions" to emptyList<Map<String, Any?>>(),
      "hingeAngle" to null,
      "horizontalSizeClass" to "unspecified",
      "verticalSizeClass" to "unspecified",
      "verticalBarEdge" to "unspecified",
    )
  }
}
