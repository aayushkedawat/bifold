package dev.bifold.bifold

import androidx.window.layout.FoldingFeature
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Covers the two rules that justify the whole capability design.
 *
 * `CapabilityReader` itself needs a `Context`, so it cannot be built in a JVM
 * test and no test ever reached this logic. Extracting it is what makes these
 * possible without adding Robolectric.
 */
class CapabilityObservationsTest {

  /// A FoldingFeature with no bounds.
  ///
  /// `bounds` is an `android.graphics.Rect`, which throws "Stub!" off-device —
  /// but nothing here reads it, so a fake that refuses it is both honest and
  /// sufficient.
  private class Fold(
    private val stateValue: FoldingFeature.State,
    private val separating: Boolean = true,
    private val occlusion: FoldingFeature.OcclusionType =
      FoldingFeature.OcclusionType.NONE,
    private val orientationValue: FoldingFeature.Orientation =
      FoldingFeature.Orientation.VERTICAL,
  ) : FoldingFeature {
    override val bounds: android.graphics.Rect
      get() = throw UnsupportedOperationException("not read by this logic")
    override val isSeparating: Boolean get() = separating
    override val occlusionType: FoldingFeature.OcclusionType get() = occlusion
    override val orientation: FoldingFeature.Orientation get() = orientationValue
    override val state: FoldingFeature.State get() = stateValue
  }

  @Test
  fun `an observation promotes, and is sticky`() {
    val o = CapabilityObservations()
    assertFalse(o.sawFold)
    assertFalse(o.sawHalfOpened)

    o.observeFolds(listOf(Fold(FoldingFeature.State.HALF_OPENED)), 0)
    assertTrue(o.sawFold)
    assertTrue(o.sawHalfOpened)

    // A closed foldable reports no folding feature at all. That must not take
    // anything away -- it is the case no runtime observation can cover, and
    // the reason the whole resolver exists.
    o.observeFolds(emptyList(), 0)
    assertTrue(o.sawFold)
    assertTrue(o.sawHalfOpened)
  }

  @Test
  fun `the revision moves on a real change`() {
    val o = CapabilityObservations()
    assertEquals(0, o.revision)

    o.observeFolds(listOf(Fold(FoldingFeature.State.FLAT)), 0)
    assertEquals(1, o.revision)

    // Half-opened is new information: a capability moves from unknown to
    // supported, so Dart has to re-query.
    o.observeFolds(listOf(Fold(FoldingFeature.State.HALF_OPENED)), 0)
    assertEquals(2, o.revision)
  }

  @Test
  fun `the revision does not move when nothing changes`() {
    val o = CapabilityObservations()
    o.observeFolds(listOf(Fold(FoldingFeature.State.HALF_OPENED)), 0)
    val settled = o.revision

    // This is the case the gate exists for: a fold in progress delivers the
    // same facts over and over while the hinge angle moves. Bumping here
    // would cost Dart a platform round trip per sensor sample, which is what
    // it did before the revision existed.
    repeat(60) {
      o.observeFolds(listOf(Fold(FoldingFeature.State.HALF_OPENED)), 0)
    }
    assertEquals(settled, o.revision)
  }

  @Test
  fun `an empty window area report is recorded, and is authoritative`() {
    val o = CapabilityObservations()
    assertFalse(o.sawWindowAreaReport)

    // EmptyWindowAreaControllerImpl emits exactly one empty list when the
    // window extensions are absent. That is a real negative, not silence.
    o.observeWindowAreas(emptyList())
    assertTrue(o.sawWindowAreaReport)
    // It changed what is known, so it must be visible to Dart.
    assertEquals(1, o.revision)

    // A second identical report says nothing new.
    o.observeWindowAreas(emptyList())
    assertEquals(1, o.revision)
  }

  @Test
  fun `new modes move the revision, repeated modes do not`() {
    val o = CapabilityObservations()
    o.observeWindowAreas(listOf("presentation"))
    val afterFirst = o.revision

    o.observeWindowAreas(listOf("presentation"))
    assertEquals(afterFirst, o.revision)

    o.observeWindowAreas(listOf("presentation", "transfer"))
    assertEquals(afterFirst + 1, o.revision)
  }

  @Test
  fun `rotation is captured with the orientation, not read later`() {
    val o = CapabilityObservations()
    // Orientation is reported relative to the current rotation, so a book
    // foldable turned through ninety degrees reports its hinge as HORIZONTAL.
    // Folding the rotation back in is what recovers "book" from that.
    o.observeFolds(
      listOf(
        Fold(
          FoldingFeature.State.HALF_OPENED,
          orientationValue = FoldingFeature.Orientation.HORIZONTAL,
        )
      ),
      1, // Surface.ROTATION_90
    )
    assertEquals("book", o.formFactor())

    // The shape must not drift afterwards. While the rotation was read live at
    // payload time, a later portrait reading combined with this orientation
    // and reported "flip" -- the same physical device changing shape.
    assertEquals("book", o.formFactor())
    assertEquals(1, o.foldRotation, "the rotation was captured, not re-read")
  }

  @Test
  fun `a shape change moves the revision`() {
    val o = CapabilityObservations()
    o.observeFolds(
      listOf(Fold(FoldingFeature.State.FLAT, orientationValue = FoldingFeature.Orientation.VERTICAL)),
      0,
    )
    val afterBook = o.revision
    assertEquals("book", o.formFactor())

    o.observeFolds(
      listOf(Fold(FoldingFeature.State.FLAT, orientationValue = FoldingFeature.Orientation.HORIZONTAL)),
      0,
    )
    assertEquals("flip", o.formFactor())
    assertEquals(afterBook + 1, o.revision)
  }
}
