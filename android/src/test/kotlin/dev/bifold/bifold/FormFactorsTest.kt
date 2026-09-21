package dev.bifold.bifold

import android.view.Surface
import androidx.window.layout.FoldingFeature
import kotlin.test.Test
import kotlin.test.assertEquals

class FormFactorsTest {

  @Test
  fun `a vertical hinge upright is a book`() {
    assertEquals(
      "book",
      FormFactors.from(FoldingFeature.Orientation.VERTICAL, Surface.ROTATION_0),
    )
  }

  @Test
  fun `a horizontal hinge upright is a flip`() {
    assertEquals(
      "flip",
      FormFactors.from(FoldingFeature.Orientation.HORIZONTAL, Surface.ROTATION_0),
    )
  }

  @Test
  fun `a book foldable turned sideways is still a book`() {
    // The bug this exists for. The hinge reports HORIZONTAL in landscape, and
    // reading it raw made a pixel_9_pro_fold announce itself as a flip phone.
    for (rotation in listOf(Surface.ROTATION_90, Surface.ROTATION_270)) {
      assertEquals(
        "book",
        FormFactors.from(FoldingFeature.Orientation.HORIZONTAL, rotation),
      )
    }
  }

  @Test
  fun `a flip foldable turned sideways is still a flip`() {
    for (rotation in listOf(Surface.ROTATION_90, Surface.ROTATION_270)) {
      assertEquals(
        "flip",
        FormFactors.from(FoldingFeature.Orientation.VERTICAL, rotation),
      )
    }
  }

  @Test
  fun `upside down is not a quarter turn`() {
    assertEquals(
      "book",
      FormFactors.from(FoldingFeature.Orientation.VERTICAL, Surface.ROTATION_180),
    )
  }

  @Test
  fun `no observed fold means no claim about shape`() {
    assertEquals("unknown", FormFactors.from(null, Surface.ROTATION_0))
  }
}
