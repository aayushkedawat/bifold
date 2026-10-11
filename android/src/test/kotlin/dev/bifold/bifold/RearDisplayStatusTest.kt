package dev.bifold.bifold

import androidx.window.area.WindowAreaCapability
import androidx.window.core.ExperimentalWindowApi
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Covers the distinction the four status spellings could not express alone.
 *
 * `RearDisplay` cannot be built without a `WindowAreaController`, so this rule
 * was unreachable from a JVM test until it was extracted into
 * [RearDisplayStatus].
 */
// The status constants live in androidx.window.area, so referencing them here
// needs the same opt-in the class under test carries.
@OptIn(ExperimentalWindowApi::class)
class RearDisplayStatusTest {

  private val available = WindowAreaCapability.Status.WINDOW_AREA_STATUS_AVAILABLE
  private val unavailable = WindowAreaCapability.Status.WINDOW_AREA_STATUS_UNAVAILABLE
  private val unsupported = WindowAreaCapability.Status.WINDOW_AREA_STATUS_UNSUPPORTED
  private val active = WindowAreaCapability.Status.WINDOW_AREA_STATUS_ACTIVE

  private fun RearDisplayStatus.answered() =
    status(presentationSessionActive = false, transferSessionActive = false)

  @Test
  fun `a later report replaces the earlier one`() {
    val s = RearDisplayStatus()
    s.observe(unavailable, unsupported)
    assertEquals("unavailable", s.answered()["presentation"])

    // The status is settled from the report rather than read out of the
    // `WindowAreaInfo` objects when asked, so a second report has to replace
    // the first for a control to follow the platform rather than a snapshot
    // taken at startup.
    s.observe(available, active)
    val answered = s.answered()
    assertEquals("available", answered["presentation"])
    assertEquals("active", answered["transfer"])
  }

  @Test
  fun `a report that names no area is a negative, not a stale positive`() {
    val s = RearDisplayStatus()
    s.observe(available, available)
    // A later emission with no window area at all means the operation is gone,
    // and must not leave the previous `available` standing.
    s.observe(null, null)

    assertEquals("unsupported", s.answered()["presentation"])
  }

  @Test
  fun `nothing reported yet is unresolved, not proven absent`() {
    val s = RearDisplayStatus()
    val answered = s.answered()

    // Both statuses read "unsupported", because a capability with no evidence
    // and a proven absence share that spelling on the wire -- there is no
    // "unknown" value, and Dart maps any unrecognised string to unsupported.
    // isResolved is therefore the only thing that stops a UI hiding a control
    // the moment it opens, before the platform has had a chance to speak.
    assertEquals("unsupported", answered["presentation"])
    assertEquals("unsupported", answered["transfer"])
    assertFalse(s.sawReport)
    assertEquals(false, answered["isResolved"])
  }

  @Test
  fun `an empty report settles, and proves absence`() {
    val s = RearDisplayStatus()
    // EmptyWindowAreaControllerImpl emits exactly one empty list when the
    // window extensions are absent. That is a real negative, not silence.
    s.observe(null, null)
    val answered = s.answered()

    assertTrue(s.sawReport)
    assertEquals(true, answered["isResolved"])
    assertEquals("unsupported", answered["presentation"])
    assertEquals("unsupported", answered["transfer"])
  }

  @Test
  fun `each reported status maps to the spelling Dart decodes`() {
    val s = RearDisplayStatus()
    s.observe(available, unsupported)
    val answered = s.answered()

    assertEquals("available", answered["presentation"])
    assertEquals("unsupported", answered["transfer"])
    assertEquals(true, answered["isResolved"])
  }

  @Test
  fun `unavailable and active pass through`() {
    val s = RearDisplayStatus()
    s.observe(unavailable, active)
    val answered = s.answered()

    assertEquals("unavailable", answered["presentation"])
    assertEquals("active", answered["transfer"])
  }

  @Test
  fun `a reported unsupported is an answer, unlike silence`() {
    val s = RearDisplayStatus()
    s.observe(unsupported, unsupported)
    val answered = s.answered()

    assertEquals("unsupported", answered["presentation"])
    // Same status as the unreported case above; the whole difference is here.
    assertEquals(true, answered["isResolved"])
  }

  @Test
  fun `a running session outranks the report`() {
    val s = RearDisplayStatus()
    s.observe(available, available)

    // A session this process started is a fact this process holds directly,
    // and the platform can lag behind it: API_NOTES records a Pixel 9 Pro Fold
    // emulator still reporting WINDOW_AREA_STATUS_ACTIVE after close(). The
    // session flag is the fact; the report is the fallback.
    val answered =
      s.status(presentationSessionActive = true, transferSessionActive = true)
    assertEquals("active", answered["presentation"])
    assertEquals("active", answered["transfer"])
  }

  @Test
  fun `a session reads active even before anything has reported`() {
    val s = RearDisplayStatus()
    val answered =
      s.status(presentationSessionActive = true, transferSessionActive = false)

    assertEquals("active", answered["presentation"])
    assertEquals("unsupported", answered["transfer"])
  }
}
