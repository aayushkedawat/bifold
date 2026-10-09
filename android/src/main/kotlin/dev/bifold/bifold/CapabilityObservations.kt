package dev.bifold.bifold

import androidx.window.layout.FoldingFeature

/**
 * The sticky observations a capability answer is derived from, and the rule
 * that decides when those answers have changed.
 *
 * Pure: no Android framework calls, no Context, nothing to mock — the inputs
 * are plain booleans and androidx's own enum objects, which resolve on the
 * JVM. This is its own file for the same reason [FormFactors] is: the logic
 * here is the least obvious in the package and the most worth testing, and
 * `CapabilityReader` cannot be constructed without a `Context`.
 *
 * Two rules live here.
 *
 * **Observations only ever add.** Seeing a half-opened posture proves the
 * device can report one; never having seen it proves nothing. So every field
 * below is sticky for the life of the process, which is what lets a foldable
 * folded shut — reporting no folding feature at all — keep the capabilities
 * it demonstrated while it was open.
 *
 * **A revision moves only on a real change.** Dart re-queries capabilities
 * when [revision] moves, so it must move for every change to a status, the
 * form factor or the rear-display modes, and for nothing else. A hinge angle
 * arriving at sensor rate must not touch it, or the gate it exists to provide
 * is worthless.
 */
internal class CapabilityObservations {

  var sawFold: Boolean = false
    private set
  var sawHalfOpened: Boolean = false
    private set
  var sawSeparating: Boolean = false
    private set
  var sawOcclusion: Boolean = false
    private set
  var foldOrientation: FoldingFeature.Orientation? = null
    private set

  /**
   * The rotation the display was at when [foldOrientation] was observed.
   *
   * `FoldingFeature.Orientation` is relative to the current rotation, so the
   * two only mean anything together. Reading the rotation live at payload time
   * instead let a vertical hinge seen in landscape combine with a later
   * portrait rotation and flip the device's shape from book to flip.
   */
  var foldRotation: Int = 0
    private set

  /**
   * Whether a window-area report has ever been delivered.
   *
   * An empty list means two different things. Before the first callback it
   * means nothing has reported. After one it is authoritative: with the window
   * extensions absent, `WindowAreaController.getOrCreate()` returns
   * `EmptyWindowAreaControllerImpl`, whose `windowAreaInfos` emits exactly one
   * empty list.
   */
  var sawWindowAreaReport: Boolean = false
    private set

  var revision: Int = 0
    private set

  /** The shape these observations imply. */
  fun formFactor(): String = FormFactors.from(foldOrientation, foldRotation)

  /**
   * Folds in an observation, bumping [revision] only if something changed.
   *
   * [rotation] is captured alongside the orientation rather than read later,
   * because the pair is what carries meaning.
   */
  fun observeFolds(folds: List<FoldingFeature>, rotation: Int) {
    if (folds.isEmpty()) return
    val before = signature()
    sawFold = true
    for (fold in folds) {
      if (fold.state == FoldingFeature.State.HALF_OPENED) sawHalfOpened = true
      if (fold.isSeparating) sawSeparating = true
      if (fold.occlusionType == FoldingFeature.OcclusionType.FULL) sawOcclusion = true
      foldOrientation = fold.orientation
      foldRotation = rotation
    }
    if (signature() != before) revision++
  }

  /**
   * Records that window areas were reported, bumping [revision] if the modes
   * they offer changed.
   *
   * [modes] is the capability-relevant projection of the report rather than
   * the report itself: androidx hands over fresh `WindowAreaInfo` instances on
   * every emission, so comparing the objects would bump on every callback.
   */
  fun observeWindowAreas(modes: List<String>) {
    val before = signature()
    sawWindowAreaReport = true
    windowAreaModes = modes
    if (signature() != before) revision++
  }

  var windowAreaModes: List<String> = emptyList()
    private set

  /** Everything a capability answer derives from, as one comparable value. */
  private fun signature(): String = listOf(
    sawFold,
    sawHalfOpened,
    sawSeparating,
    sawOcclusion,
    formFactor(),
    sawWindowAreaReport,
    windowAreaModes,
  ).joinToString("|")
}
