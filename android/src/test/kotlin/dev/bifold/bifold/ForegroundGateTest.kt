package dev.bifold.bifold

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Covers the rules that make the foreground gate safe to add at all.
 *
 * The first is the configuration-change guard. Without it, gating the hinge
 * sensor on "the app is on screen" would have reintroduced a bug this plugin
 * already fixed once: a configuration change is a stop, folding is a
 * configuration change, and `HingeReader.stop()` clears the angle to null
 * because an unregistered sensor has no current reading. Folding the device
 * would then erase the hinge angle mid-gesture — the one moment an app reading
 * it cares about.
 *
 * The second is that the gate counts rather than latches, because Android
 * delivers the newcomer's start before the outgoing activity's stop.
 *
 * The third is that a start sets the flag unconditionally, credit or no credit:
 * skipping that on a credited start is the only way the gate can be made to
 * fail closed, holding the sensor off with an activity in front of the user.
 */
class ForegroundGateTest {

  @Test
  fun `a background stop clears it, and a start restores it`() {
    val gate = ForegroundGate()
    assertTrue(gate.foreground, "fails open before anything is observed")

    gate.started()
    gate.stopped(changingConfigurations = false)
    assertFalse(gate.foreground)

    gate.started()
    assertTrue(gate.foreground)
  }

  @Test
  fun `a configuration change is not a backgrounding`() {
    val gate = ForegroundGate()
    gate.started()

    gate.stopped(changingConfigurations = true)
    assertTrue(
      gate.foreground,
      "a fold stops the activity, and must not read as leaving the screen",
    )
  }

  @Test
  fun `the activity reborn after a configuration change does not drift the count`() {
    val gate = ForegroundGate()
    gate.started()

    // The fold: the outgoing activity stops for recreation, and the incoming
    // one starts. Counting that start would leave the total one too high.
    gate.stopped(changingConfigurations = true)
    gate.started()

    gate.stopped(changingConfigurations = false)
    assertFalse(
      gate.foreground,
      "after a fold the gate must still fall back on a real backgrounding",
    )
  }

  @Test
  fun `a second activity on screen keeps it foreground`() {
    val gate = ForegroundGate()
    gate.started()

    // The newcomer starts before the activity it covers stops, so a boolean
    // would clear on that stop and stay cleared while the app is still visible.
    gate.started()
    gate.stopped(changingConfigurations = false)
    assertTrue(
      gate.foreground,
      "only one of the app's activities stopped; it is still on screen",
    )

    gate.stopped(changingConfigurations = false)
    assertFalse(gate.foreground)
  }

  @Test
  fun `a start that answers a skipped stop still means something is on screen`() {
    val gate = ForegroundGate()

    // No start was ever seen for the activities already on screen -- a cached
    // engine, add-to-app, or an engine attached to a host activity that had
    // already started -- so the count begins behind and the first real stop
    // clears the flag even though one of them is still visible.
    gate.stopped(changingConfigurations = true)
    gate.stopped(changingConfigurations = false)
    assertFalse(gate.foreground, "the count was already behind, so this cleared")

    // The folded activity's replacement now starts. Consuming the credit must
    // not skip the one thing that callback proves: this app is on screen.
    gate.started()
    assertTrue(
      gate.foreground,
      "a started activity is on screen whatever the count says",
    )
  }
}
