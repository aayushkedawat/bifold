import Flutter
import UIKit

/// Channel names. These must match `lib/src/method_channel_bifold.dart`.
private enum Channels {
  static let methods = "dev.bifold/methods"
  static let events = "dev.bifold/fold_info"
}

/// Stable error codes surfaced to Dart as `FlutterError`.
///
/// Dart treats every one of these as "no fold information", so they are
/// diagnostic rather than recoverable.
private enum ErrorCode {
  static let noView = "no_view"
  static let unsupported = "unsupported_os"
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
      result(foldReader.read(from: view, version: payloadVersion))
    case "isSupported":
      result(FoldReader.isSupported)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// The `UIView` backing the Flutter view controller.
  ///
  /// Reserved regions are a property of a specific view, so every reading is
  /// taken from this one. Returns nil before the view controller is attached.
  private func flutterView() -> UIView? {
    // `view` on the registrar's view controller is the documented access path
    // to the Flutter view from a plugin.
    return registrar?.view()
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
    events(foldReader.read(from: view, version: payloadVersion))

    observation = foldReader.observe(view: view) { [weak self] in
      guard let self, let sink = self.eventSink, let view = self.flutterView()
      else { return }
      sink(self.foldReader.read(from: view, version: payloadVersion))
    }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    observation?.cancel()
    observation = nil
    eventSink = nil
    return nil
  }
}
