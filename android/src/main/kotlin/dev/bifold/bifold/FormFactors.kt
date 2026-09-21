package dev.bifold.bifold

import android.view.Surface
import androidx.window.layout.FoldingFeature

/**
 * Works out a device's shape from a hinge orientation and a screen rotation.
 *
 * Pure: no Android framework calls, no context, nothing to mock. The rotation
 * constants are compile-time ints and the orientations are plain Kotlin
 * objects, so this is unit-testable on the JVM without Robolectric — which is
 * the reason it is its own file rather than a private method.
 */
internal object FormFactors {

  /**
   * The shape, or `"unknown"` when there is not enough to say.
   *
   * [FoldingFeature.Orientation] describes the hinge relative to the *current*
   * display rotation rather than to the device. A book foldable turned through
   * ninety degrees reports its vertical hinge as `HORIZONTAL`, which reads as a
   * flip phone unless the rotation is folded back in. Observed on a
   * `pixel_9_pro_fold` emulator in landscape.
   *
   * `dualScreen` is never returned: orientation cannot distinguish one
   * flexible display from two physical ones.
   */
  fun from(orientation: FoldingFeature.Orientation?, rotation: Int): String {
    if (orientation == null) return "unknown"
    val quarterTurned =
      rotation == Surface.ROTATION_90 || rotation == Surface.ROTATION_270
    val upright = if (quarterTurned) opposite(orientation) else orientation
    return when (upright) {
      FoldingFeature.Orientation.VERTICAL -> "book"
      FoldingFeature.Orientation.HORIZONTAL -> "flip"
      else -> "unknown"
    }
  }

  private fun opposite(orientation: FoldingFeature.Orientation) =
    when (orientation) {
      FoldingFeature.Orientation.VERTICAL -> FoldingFeature.Orientation.HORIZONTAL
      FoldingFeature.Orientation.HORIZONTAL -> FoldingFeature.Orientation.VERTICAL
      else -> orientation
    }
}
