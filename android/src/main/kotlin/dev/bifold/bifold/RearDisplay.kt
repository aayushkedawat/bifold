package dev.bifold.bifold

import android.app.Activity
import android.os.Binder
import androidx.window.area.WindowAreaCapability
import androidx.window.area.WindowAreaController
import androidx.window.area.WindowAreaInfo
import androidx.window.area.WindowAreaPresentationSessionCallback
import androidx.window.area.WindowAreaSession
import androidx.window.area.WindowAreaSessionCallback
import androidx.window.area.WindowAreaSessionPresenter
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor
import java.util.concurrent.Executor

/**
 * Puts app content on the display that faces the rear camera.
 *
 * Two operations, which are different things and are kept apart:
 *
 * * **presentation** — content appears on the second display while the app
 *   stays on the first. This is what the foldable iPhone's capture accessory
 *   does, and it needs its own Flutter engine, because a Flutter engine
 *   renders one view tree.
 * * **transfer** — the whole activity moves to the second display. Android
 *   only; there is no iOS equivalent.
 *
 * The system owns the session either way: it can end one at any time, and
 * [WindowAreaPresentationSessionCallback.onSessionEnded] is the only reliable
 * signal that it has.
 */
internal class RearDisplay(
  private val controller: WindowAreaController,
  private val executor: Executor,
  private val onStatusChanged: () -> Unit,
) {

  private var areas: List<WindowAreaInfo> = emptyList()
  private var presentationSession: WindowAreaSessionPresenter? = null
  private var transferSession: WindowAreaSession? = null

  /** The engine backing presented content, torn down with the session. */
  private var engine: FlutterEngine? = null
  private var flutterView: FlutterView? = null

  fun observe(infos: List<WindowAreaInfo>) {
    areas = infos
    onStatusChanged()
  }

  /**
   * The current status of each operation.
   *
   * `active` is reported from the session held here rather than from the
   * capability status, because a session this process started is something
   * this process knows for certain.
   */
  fun status(): Map<String, String> = mapOf(
    "presentation" to statusOf(PRESENT, presentationSession != null),
    "transfer" to statusOf(TRANSFER, transferSession != null),
  )

  private fun statusOf(
    operation: WindowAreaCapability.Operation,
    sessionActive: Boolean,
  ): String {
    if (sessionActive) return "active"
    val info = areas.firstOrNull() ?: return "unsupported"
    return when (info.getCapability(operation).status) {
      WindowAreaCapability.Status.WINDOW_AREA_STATUS_AVAILABLE -> "available"
      WindowAreaCapability.Status.WINDOW_AREA_STATUS_UNAVAILABLE -> "unavailable"
      WindowAreaCapability.Status.WINDOW_AREA_STATUS_ACTIVE -> "active"
      else -> "unsupported"
    }
  }

  /**
   * Shows [entrypoint]'s content on the rear display.
   *
   * Returns false when the operation is not available, which is not an error:
   * the device may not support it, or the system may not be willing right now.
   */
  fun present(activity: Activity, entrypoint: String, libraryUri: String?): Boolean {
    val info = areas.firstOrNull() ?: return false
    if (info.getCapability(PRESENT).status !=
      WindowAreaCapability.Status.WINDOW_AREA_STATUS_AVAILABLE
    ) {
      return false
    }

    controller.presentContentOnWindowArea(
      info.token,
      activity,
      executor,
      object : WindowAreaPresentationSessionCallback {
        override fun onSessionStarted(session: WindowAreaSessionPresenter) {
          presentationSession = session
          // A second engine, because one engine renders one view tree. The
          // entrypoint must be annotated @pragma('vm:entry-point') or the
          // compiler drops it from a release build.
          val group = FlutterEngineGroup(session.context)
          val bundle = FlutterInjector.instance().flutterLoader().findAppBundlePath()
          // The three-argument form needs a non-null library; the two-argument
          // one defaults to the app's main library, which is where an
          // entrypoint usually lives.
          val dartEntrypoint = if (libraryUri == null) {
            DartExecutor.DartEntrypoint(bundle, entrypoint)
          } else {
            DartExecutor.DartEntrypoint(bundle, libraryUri, entrypoint)
          }
          val created = group.createAndRunEngine(session.context, dartEntrypoint)
          val view = FlutterView(session.context)
          view.attachToFlutterEngine(created)
          engine = created
          flutterView = view
          session.setContentView(view)
          onStatusChanged()
        }

        override fun onSessionEnded(t: Throwable?) {
          // Reached whether the app ended the session or the system did, so
          // it is the only correct place to tear the engine down.
          releasePresentation()
          onStatusChanged()
        }

        override fun onContainerVisibilityChanged(isVisible: Boolean) {
          onStatusChanged()
        }
      },
    )
    return true
  }

  /** Moves the whole activity to the rear display. */
  fun transfer(activity: Activity): Boolean {
    val info = areas.firstOrNull() ?: return false
    if (info.getCapability(TRANSFER).status !=
      WindowAreaCapability.Status.WINDOW_AREA_STATUS_AVAILABLE
    ) {
      return false
    }

    controller.transferActivityToWindowArea(
      info.token,
      activity,
      executor,
      object : WindowAreaSessionCallback {
        override fun onSessionStarted(session: WindowAreaSession) {
          transferSession = session
          onStatusChanged()
        }

        override fun onSessionEnded(t: Throwable?) {
          // Reached whether the app ended it or the system did.
          transferSession = null
          onStatusChanged()
        }
      },
    )
    return true
  }

  /**
   * Ends whichever session is running. Safe to call when none is.
   *
   * Closes the session *and* releases the engine locally. `onSessionEnded` is
   * the documented signal and is still handled, because the system can end a
   * session on its own, but it cannot be relied on as the only path: see the
   * limitation below. Releasing here too is safe because
   * [releasePresentation] is idempotent — every step is null-checked and nulls
   * what it touched, so a device that *does* deliver the callback simply
   * releases twice and the second is a no-op.
   *
   * **Known limitation, observed on the Android 37.2 emulator.** Closing does
   * not end the session as far as the platform is concerned: `onSessionEnded`
   * never arrives, and `WindowAreaInfo` keeps reporting
   * `WINDOW_AREA_STATUS_ACTIVE` indefinitely. The second engine is torn down
   * correctly, so nothing leaks, but the reported status stays `active`. That
   * status is passed through rather than corrected, because inventing an
   * `available` the platform is not reporting is exactly the kind of claim
   * this package refuses to make elsewhere. Unverified on hardware; a real
   * device may well behave correctly.
   */
  fun end() {
    presentationSession?.close()
    transferSession?.close()
    releasePresentation()
    transferSession = null
    onStatusChanged()
  }

  private fun releasePresentation() {
    flutterView?.detachFromFlutterEngine()
    engine?.destroy()
    flutterView = null
    engine = null
    presentationSession = null
  }

  private companion object {
    val PRESENT = WindowAreaCapability.Operation.OPERATION_PRESENT_ON_AREA
    val TRANSFER = WindowAreaCapability.Operation.OPERATION_TRANSFER_ACTIVITY_TO_AREA
  }
}
