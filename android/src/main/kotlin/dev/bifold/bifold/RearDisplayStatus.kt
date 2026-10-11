package dev.bifold.bifold

import androidx.window.area.WindowAreaCapability
import androidx.window.core.ExperimentalWindowApi

/**
 * The availability answer for the two rear-display operations, and the rule
 * that decides when it is an answer at all.
 *
 * Three separate facts are easy to conflate here, and the brief forbids
 * conflating them:
 *
 * * **capability** — the device offers the operation at all;
 * * **availability** — it can be used right now, which the platform reports as
 *   `unavailable`, `available` or `active`;
 * * **resolution** — whether anything has been reported yet.
 *
 * The first two share one field because the platform already keeps them in one
 * enum: `WINDOW_AREA_STATUS_UNSUPPORTED` is a capability claim and the rest is
 * availability. A session *this* process started is reported `active` from the
 * session flags rather than from the platform, because that is something this
 * process knows for certain.
 *
 * Resolution is the one Dart cannot infer for itself. `WindowAreaController`
 * reports nothing until its first callback, and before that an empty area list
 * means "nothing has reported", not "unsupported" — the same distinction
 * `CapabilityReader` draws between `not_yet_reported` and `no_window_areas`.
 * Dart reads `isResolved` strictly and has no "unknown" status spelling, so an
 * unsettled answer has to travel on that key; the statuses stay the settled
 * ones they have always been.
 *
 * Pure: the only androidx type it touches is `WindowAreaCapability.Status`, a
 * plain class whose constants are `@JvmField` singletons, so it resolves on
 * the JVM — which is why this is its own file, the way
 * [CapabilityObservations] is.
 */
// Status lives in androidx.window.area, so every symbol touched here is
// @ExperimentalWindowApi. See API_NOTES.md.
@OptIn(ExperimentalWindowApi::class)
internal class RearDisplayStatus {

  /**
   * Whether a window-area report has ever been delivered.
   *
   * Before the first callback this is false and every operation reads
   * `unsupported` while `isResolved` reads false, so Dart can tell "this device
   * cannot present" from "nothing has spoken yet".
   */
  var sawReport: Boolean = false
    private set

  /** The last reported capability status per operation, absent when unreported. */
  private var reported: Map<String, WindowAreaCapability.Status> = emptyMap()

  /**
   * Folds in a window-area report.
   *
   * Each argument is the capability status for that operation, or null when no
   * window area was reported at all — which is a real negative after the first
   * report, and silence before it.
   */
  fun observe(
    presentation: WindowAreaCapability.Status?,
    transfer: WindowAreaCapability.Status?,
  ) {
    sawReport = true
    val next = mutableMapOf<String, WindowAreaCapability.Status>()
    if (presentation != null) next[PRESENTATION] = presentation
    if (transfer != null) next[TRANSFER] = transfer
    reported = next
  }

  /**
   * The payload Dart decodes, one entry per operation plus `isResolved`.
   *
   * A running session outranks the platform's report, because a session held
   * here is not a guess.
   */
  fun status(
    presentationSessionActive: Boolean,
    transferSessionActive: Boolean,
  ): Map<String, Any> = mapOf(
    PRESENTATION to statusOf(PRESENTATION, presentationSessionActive),
    TRANSFER to statusOf(TRANSFER, transferSessionActive),
    "isResolved" to sawReport,
  )

  private fun statusOf(operation: String, sessionActive: Boolean): String {
    if (sessionActive) return ACTIVE
    val status = reported[operation] ?: return UNSUPPORTED
    return when (status) {
      WindowAreaCapability.Status.WINDOW_AREA_STATUS_AVAILABLE -> AVAILABLE
      WindowAreaCapability.Status.WINDOW_AREA_STATUS_UNAVAILABLE -> UNAVAILABLE
      WindowAreaCapability.Status.WINDOW_AREA_STATUS_ACTIVE -> ACTIVE
      // UNSUPPORTED, and anything a future androidx adds. An unrecognised
      // status must never read as support: Dart maps unknown spellings to
      // `unsupported` anyway, and claiming more than we know is the one thing
      // this package refuses.
      else -> UNSUPPORTED
    }
  }

  private companion object {
    const val PRESENTATION = "presentation"
    const val TRANSFER = "transfer"
    const val UNSUPPORTED = "unsupported"
    const val UNAVAILABLE = "unavailable"
    const val AVAILABLE = "available"
    const val ACTIVE = "active"
  }
}
