package dev.bifold.bifold

/**
 * Whether the app is on screen, so the hinge sensor is only held while it is.
 *
 * The sensor follows two things: whether anyone is listening, and whether the
 * app is in front. Only the first was ever consulted, so a listener that was
 * never cancelled kept `Sensor.TYPE_HINGE_ANGLE` registered across the whole
 * background lifetime of the process — a sensor running at
 * `SENSOR_DELAY_NORMAL` for an app nobody is looking at.
 *
 * # On screen is start/stop, not resume/pause
 *
 * "On screen" is `onActivityStarted` / `onActivityStopped`. Resume and pause
 * track *focus*, and Android documents a paused activity that is still visible:
 * `onResume` is "usually a hint for your activity to start interacting with the
 * user", and its own javadoc gives the case — an activity "may be relaunched to
 * `onPause` due to configuration changes and the activity was visible, but
 * wasn't the top-most activity of an activity task"
 * (`android/app/Activity.java:2231-2238`). Before API 29 only one activity in
 * the system could be resumed at a time (`:2242-2244`), so in split screen,
 * under a translucent activity, or in picture-in-picture, a visible app is
 * paused. Gating on pause would release the sensor — and
 * [HingeReader.stop] clears the angle to null — while the app was on screen and
 * foldable, which is the one state this package exists to report.
 *
 * # Why it counts rather than latches
 *
 * One boolean cannot answer this, because the callbacks are per activity and an
 * app can have more than one of its own on screen. A second activity starting
 * over the first runs `onActivityStarted` for the newcomer *before*
 * `onActivityStopped` for the activity it covers, so a boolean would clear the
 * flag on that stop and leave it cleared while the newcomer is visible — with
 * no further callback to put it back. Counting started activities keeps the
 * answer right through the transition.
 *
 * # Why the configuration-change guard is still needed
 *
 * A fold is a configuration change, and a configuration change tears the
 * activity down: pause, stop, destroy, create, start, resume.
 * `onActivityStopped` therefore fires partway through the one gesture this
 * package reports, and [HingeReader.stop] clears the angle to null because an
 * unregistered sensor has no current reading. Acting on that stop would erase
 * the hinge angle mid-fold — the exact dropout [BifoldPlugin.stopObserving]
 * documents having already fixed once; this must not put it back.
 *
 * `Activity.isChangingConfigurations()` is the documented way to tell the two
 * apart — "whether this activity is in the process of being destroyed in order
 * to be recreated in another configuration"
 * (`android/app/Activity.java:7468`) — and it is literally about teardown,
 * which is when the guarded stop arrives. `Activity.onStop` reads that same
 * flag for its own bookkeeping (`Activity.java:2928`).
 *
 * The skipped stop is remembered rather than ignored, so the replacement
 * activity's start is not counted either. Without that pairing every fold would
 * leave the count one too high, and the gate would never fall back on the next
 * real backgrounding.
 *
 * Pure: the state is an int, so the rule is testable on the JVM without an
 * `Activity`. The caller reads the Android property and passes it in.
 *
 * Fails open. [foreground] starts true, every start sets it true, and only a
 * non-recreation stop is allowed to clear it, so a process that cannot register
 * its lifecycle callbacks — or that registers after its activities have already
 * started and therefore begins with a count behind — keeps the sensor behaving
 * exactly as it did before this gate existed, rather than silently losing hinge
 * readings.
 *
 * The cost of that choice is one state it cannot see out of: if a skipped
 * stop's replacement start never arrives — the user folds, then leaves for Home
 * before the relaunch starts — the credit and the count both stay high and the
 * sensor keeps running until the next real stop. That is the fail-open
 * direction, and it heals on the next backgrounding; see `doc/manual-tests.md`.
 */
internal class ForegroundGate {

  /** Started activities, less any whose stop was skipped as a recreation. */
  private var onScreen: Int = 0

  /** Recreation stops seen, whose matching starts must therefore not count. */
  private var recreating: Int = 0

  /** Whether this app currently has an activity on screen. */
  var foreground: Boolean = true
    private set

  fun started() {
    // Set before the branch, not after it. `onActivityStarted` proves this app
    // has an activity on screen — nothing else can produce that callback — and
    // that holds for the reborn activity too. Leaving it below the early return
    // let a credited start skip it, which is fail-closed: a process that
    // registered after its activities had already started begins with a count
    // of zero, so the first real stop clears the flag, and the start that
    // answers a folded activity's skipped stop then declined to restore it
    // while that activity was in front of the user.
    foreground = true

    // A start that answers a skipped stop belongs to the same activity, reborn,
    // so counting it would drift the total upward on every fold.
    if (recreating > 0) {
      recreating -= 1
      return
    }
    onScreen += 1
  }

  /**
   * A stop clears the flag only once nothing of this app is left on screen.
   *
   * See the class comment for why a configuration change is not a backgrounding
   * and must not be acted on.
   */
  fun stopped(changingConfigurations: Boolean) {
    if (changingConfigurations) {
      recreating += 1
      return
    }
    onScreen = (onScreen - 1).coerceAtLeast(0)
    foreground = onScreen > 0
  }
}
