import Flutter
import UIKit

/// Channel names. These must match `lib/src/method_channel_bifold.dart`.
private enum Channels {
  static let methods = "dev.bifold/methods"
  static let events = "dev.bifold/fold_info"
  static let accessoryEvents = "dev.bifold/capture_accessory"
}

/// Stable error codes surfaced to Dart as `FlutterError`.
///
/// Dart treats every one of these as "no fold information", so they are
/// diagnostic rather than recoverable.
private enum ErrorCode {
  static let noView = "no_view"
  static let unsupported = "unsupported_os"
  static let badArguments = "bad_arguments"
}

/// The payload version stamped on every message.
///
/// Must match `kBifoldPayloadVersion` in `lib/src/models.dart`. Bump both
/// together, and only when the shape changes incompatibly.
private let payloadVersion = 1

public class BifoldPlugin: NSObject, FlutterPlugin {
  private let foldReader: FoldReader
  private var eventSink: FlutterEventSink?
  private var observation: FoldObservation?

  /// Sink for capture-accessory availability, when Dart is listening.
  private var accessorySink: FlutterEventSink?

  /// The last payload sent, so an unchanged state is not resent.
  ///
  /// `layoutSubviews` fires far more often than the fold state changes, and
  /// the hinge pushes its own updates on top. Dart already ignores an
  /// unchanged `FoldInfo`, but dropping duplicates here keeps them off the
  /// channel entirely.
  private var lastPayload: NSDictionary?

  /// The registrar is retained so the plugin can find the Flutter view lazily.
  ///
  /// At registration time the view controller's view has not been laid out, and
  /// reserved regions do not exist until after the first layout pass, so
  /// resolving the view eagerly here would always come up empty.
  private weak var registrar: (NSObjectProtocol & FlutterPluginRegistrar)?

  init(registrar: NSObjectProtocol & FlutterPluginRegistrar) {
    self.registrar = registrar
    self.foldReader = FoldReader()
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = BifoldPlugin(registrar: registrar)

    let methodChannel = FlutterMethodChannel(
      name: Channels.methods,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: methodChannel)

    let eventChannel = FlutterEventChannel(
      name: Channels.events,
      binaryMessenger: registrar.messenger()
    )
    eventChannel.setStreamHandler(instance)

    let accessoryChannel = FlutterEventChannel(
      name: Channels.accessoryEvents,
      binaryMessenger: registrar.messenger()
    )
    accessoryChannel.setStreamHandler(
      CaptureAccessoryStreamHandler(plugin: instance)
    )
  }

  /// Wires the accessory availability stream to the plugin.
  fileprivate func setAccessorySink(_ sink: FlutterEventSink?) {
    accessorySink = sink
    if #available(iOS 27.1, *), let sink {
      sink(CaptureAccessory.shared?.isAvailable ?? false)
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getFoldInfo":
      guard let view = flutterView() else {
        result(
          FlutterError(
            code: ErrorCode.noView,
            message: "The Flutter view is not available yet.",
            details: nil
          )
        )
        return
      }
      // Attach the hinge if nothing has yet, so that repeated one-shot reads
      // gain a pose and angle even when no one is listening to the stream.
      // The first such read still predates the hinge's initial update, which
      // is why the stream is the documented way to track fold state.
      foldReader.hinge.attach(to: view, onChange: {})
      result(foldReader.read(from: view, version: payloadVersion))
    case "isSupported":
      result(FoldReader.isSupported)
    case "debugDescribeNativeApi":
      result(NativeApiProbe.describe(view: flutterView()))

    case "captureAccessorySupported":
      if #available(iOS 27.1, *) {
        result(CaptureAccessory.isSupported)
      } else {
        result(false)
      }

    case "registerCaptureAccessory":
      guard #available(iOS 27.1, *) else {
        result(false)
        return
      }
      guard let args = call.arguments as? [String: Any],
        let entrypoint = args["entrypoint"] as? String
      else {
        result(
          FlutterError(
            code: ErrorCode.badArguments,
            message: "registerCaptureAccessory requires an entrypoint.",
            details: nil
          )
        )
        return
      }
      guard let host = registrar?.viewController else {
        result(
          FlutterError(
            code: ErrorCode.noView,
            message: "The Flutter view controller is not available yet.",
            details: nil
          )
        )
        return
      }
      let registered = CaptureAccessory.register(
        on: host,
        entrypoint: entrypoint,
        libraryURI: args["libraryUri"] as? String
      )
      if registered {
        CaptureAccessory.shared?.onAvailabilityChanged = { [weak self] available in
          self?.accessorySink?(available)
        }
      }
      result(registered)

    case "unregisterCaptureAccessory":
      if #available(iOS 27.1, *) {
        CaptureAccessory.unregister()
      }
      result(nil)

    case "setCaptureAccessoryEnabled":
      guard #available(iOS 27.1, *) else {
        result(nil)
        return
      }
      let enabled = (call.arguments as? [String: Any])?["enabled"] as? Bool
      CaptureAccessory.shared?.isEnabled = enabled ?? false
      result(nil)

    case "isCaptureAccessoryAvailable":
      if #available(iOS 27.1, *) {
        result(CaptureAccessory.shared?.isAvailable ?? false)
      } else {
        result(false)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// The `UIView` backing the Flutter view controller.
  ///
  /// Reserved regions are a property of a specific view, so every reading is
  /// taken from this one. Returns nil before the view controller is attached,
  /// which is the normal state at registration time.
  ///
  /// VERIFIED: `FlutterPluginRegistrar.viewController` is declared in
  /// `Flutter.framework/Headers/FlutterPlugin.h` as
  /// `@property(nullable, readonly) UIViewController* viewController;`,
  /// documented there as "the `UIViewController` whose view is displaying
  /// Flutter content". Its `view` is therefore the view reserved regions
  /// should be read from.
  private func flutterView() -> UIView? {
    // `isViewLoaded` avoids forcing the view to load early, which would
    // trigger a layout pass before UIKit is ready to report regions.
    guard let controller = registrar?.viewController, controller.isViewLoaded
    else {
      return nil
    }
    return controller.view
  }
}

// MARK: - Streaming

extension BifoldPlugin: FlutterStreamHandler {
  public func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events

    guard let view = flutterView() else {
      // Report the unsupported state rather than failing: Dart treats a stream
      // that never emits as a hang, and an app on a non-foldable device is a
      // perfectly normal case.
      events(FoldReader.unsupportedPayload(version: payloadVersion))
      return nil
    }

    // Emit immediately so the first frame has something, then again on every
    // change. Regions arrive after the first layout pass, so this first value
    // will usually report none.
    emit(from: view, to: events)

    observation = foldReader.observe(view: view) { [weak self] in
      guard let self, let sink = self.eventSink, let view = self.flutterView()
      else { return }
      self.emit(from: view, to: sink)
    }
    return nil
  }

  /// Sends a reading, unless it is identical to the previous one.
  private func emit(from view: UIView, to sink: FlutterEventSink) {
    let payload = foldReader.read(from: view, version: payloadVersion)
    let boxed = payload as NSDictionary
    guard boxed != lastPayload else { return }
    lastPayload = boxed
    sink(payload)
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    observation?.cancel()
    observation = nil
    eventSink = nil
    lastPayload = nil
    return nil
  }
}


/// Stream handler for capture-accessory availability.
///
/// Separate from the fold stream so that listening for one does not start the
/// other. Availability is pushed from the layout lifecycle, which is where
/// UIKit documents the value as observable.
private final class CaptureAccessoryStreamHandler: NSObject, FlutterStreamHandler {
  private weak var plugin: BifoldPlugin?

  init(plugin: BifoldPlugin) {
    self.plugin = plugin
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    plugin?.setAccessorySink(events)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    plugin?.setAccessorySink(nil)
    return nil
  }
}
