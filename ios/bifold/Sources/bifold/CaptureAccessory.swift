import Flutter
import ObjectiveC
import UIKit

/// Presents Flutter content on the outer display while the camera is capturing.
///
/// With the device open and a capture session running, the system can show
/// app-provided content on the outer display — to the person being filmed.
/// The canonical uses are letting a subject see their own framing, and a
/// teleprompter.
///
/// # Verification
///
/// Verified against the iOS 27.1 SDK on 2026-09-20:
///
/// ```objc
/// // UISceneAccessory.h
/// + (instancetype)cameraCaptureSceneAccessoryWithConfiguration:
///     (UISceneConfiguration *)sceneConfiguration API_AVAILABLE(ios(27.1));
///
/// // UIViewController.h
/// - (UISceneAccessoryRegistration *)registerSceneAccessory:(UISceneAccessory *)accessory
///     API_AVAILABLE(ios(27.0));
/// - (void)unregisterSceneAccessory:(UISceneAccessoryRegistration *)registration;
///
/// // UISceneAccessoryRegistration.h
/// @property (nonatomic, readonly, getter=isAvailable) BOOL available;
/// @property (nonatomic, readwrite, getter=isEnabled) BOOL enabled;
/// ```
///
/// These live in **UIKit**, not only SwiftUI. Widely repeated community
/// reporting says the camera accessory is SwiftUI-only and invisible to
/// Objective-C; the headers show otherwise, and this class is the proof.
/// SwiftUI's `CameraCaptureAccessory` is a wrapper over the same machinery.
///
/// # How the content is rendered
///
/// The system connects a *second* `UIWindowScene` for the accessory, with role
/// `UIWindowSceneSessionRoleCameraCaptureAccessory`. It needs its own Flutter
/// UI, so a second engine is created from a `FlutterEngineGroup` running a
/// separate Dart entrypoint. The app's main UI on the inner display is
/// untouched.
///
/// The system decides whether and when to present it. `enabled` is the app
/// saying it *would like* to be shown; `available` is the system saying it can
/// be. An app must remain fully functional when it never appears.
@available(iOS 27.1, *)
final class CaptureAccessory: NSObject {

  /// The single live accessory, if one is registered.
  ///
  /// Static because the scene delegate is instantiated by UIKit, which gives
  /// no way to inject the engine group into it.
  static private(set) var shared: CaptureAccessory?

  /// The Dart entrypoint the accessory UI runs.
  let entrypoint: String

  /// The Dart library the entrypoint lives in, or nil for `main.dart`.
  let libraryURI: String?

  /// Engines for accessory scenes are made from this group.
  let engineGroup: FlutterEngineGroup

  /// Called when the system's availability for the accessory changes.
  var onAvailabilityChanged: ((Bool) -> Void)?

  private var registration: NSObject?
  private weak var host: UIViewController?
  private var lastAvailability: Bool?

  private init(entrypoint: String, libraryURI: String?) {
    self.entrypoint = entrypoint
    self.libraryURI = libraryURI
    self.engineGroup = FlutterEngineGroup(
      name: "bifold.capture-accessory",
      project: nil
    )
    super.init()
  }

  /// Whether this OS can present a camera capture accessory at all.
  static var isSupported: Bool {
    guard let cls = NSClassFromString("UISceneAccessory"),
      let meta = object_getClass(cls)
    else {
      return false
    }
    return class_respondsToSelector(
      meta,
      NSSelectorFromString("cameraCaptureSceneAccessoryWithConfiguration:")
    )
  }

  /// Registers an accessory whose content runs `entrypoint`.
  ///
  /// Returns false when the OS cannot present one, which is the correct
  /// degraded answer rather than an error.
  @discardableResult
  static func register(
    on host: UIViewController,
    entrypoint: String,
    libraryURI: String?
  ) -> Bool {
    guard isSupported else { return false }

    unregister()

    let accessory = CaptureAccessory(
      entrypoint: entrypoint,
      libraryURI: libraryURI
    )
    guard accessory.attach(to: host) else { return false }
    shared = accessory
    return true
  }

  /// Tears down the current registration, if any.
  static func unregister() {
    shared?.detach()
    shared = nil
  }

  /// Whether the system currently says the accessory can be presented.
  var isAvailable: Bool {
    (registration?.value(forKey: "available") as? Bool) ?? false
  }

  /// Whether the app is asking for the accessory to be shown.
  var isEnabled: Bool {
    get { (registration?.value(forKey: "enabled") as? Bool) ?? false }
    set { registration?.setValue(newValue, forKey: "enabled") }
  }

  private func attach(to host: UIViewController) -> Bool {
    // A scene configuration with no name, the accessory session role, and our
    // own delegate class. UIKit instantiates that delegate when it connects
    // the scene.
    let role = UISceneSession.Role(
      rawValue: "UIWindowSceneSessionRoleCameraCaptureAccessory"
    )
    let configuration = UISceneConfiguration(name: nil, sessionRole: role)
    configuration.delegateClass = CaptureAccessorySceneDelegate.self

    let selector = NSSelectorFromString(
      "cameraCaptureSceneAccessoryWithConfiguration:"
    )
    guard let accessoryClass = NSClassFromString("UISceneAccessory"),
      let accessory = (accessoryClass as AnyObject)
        .perform(selector, with: configuration)?.takeUnretainedValue()
        as? NSObject
    else {
      return false
    }

    let registerSelector = NSSelectorFromString("registerSceneAccessory:")
    guard host.responds(to: registerSelector),
      let created = host.perform(registerSelector, with: accessory)?
        .takeUnretainedValue() as? NSObject
    else {
      return false
    }

    registration = created
    self.host = host
    lastAvailability = nil
    return true
  }

  /// Re-reads `available` and reports it if it changed.
  ///
  /// The header states this value "is observable during the
  /// `updateProperties` and `layoutSubviews` lifecycle events" — UIKit's
  /// observation-tracking system, not classic KVO, so there is no key path to
  /// subscribe to from a runtime-resolved property. Calling this from the
  /// layout sentinel lands on exactly the lifecycle event Apple names.
  func refreshAvailability() {
    let current = isAvailable
    guard current != lastAvailability else { return }
    lastAvailability = current
    onAvailabilityChanged?(current)
  }

  private func detach() {
    lastAvailability = nil
    if let registration, let host {
      let selector = NSSelectorFromString("unregisterSceneAccessory:")
      if host.responds(to: selector) {
        _ = host.perform(selector, with: registration)
      }
    }
    registration = nil
    host = nil
  }
}

/// Hosts the Flutter UI the system shows on the outer display.
///
/// UIKit instantiates this itself, from the `delegateClass` on the scene
/// configuration, so it takes everything it needs from
/// `CaptureAccessory.shared`.
@available(iOS 27.1, *)
final class CaptureAccessorySceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  private var engine: FlutterEngine?

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene,
      let accessory = CaptureAccessory.shared
    else {
      return
    }

    // A second engine, not a second view on the existing one: this scene has
    // its own lifecycle and its own Dart entrypoint.
    let created = accessory.engineGroup.makeEngine(
      withEntrypoint: accessory.entrypoint,
      libraryURI: accessory.libraryURI
    )
    // Plugins are registered on the accessory engine too, so the same Dart
    // code can use them. The generated registrant is looked up dynamically
    // because a plugin cannot import the host app's generated header.
    CaptureAccessorySceneDelegate.registerPlugins(with: created)

    let controller = FlutterViewController(
      engine: created,
      nibName: nil,
      bundle: nil
    )
    let created_window = UIWindow(windowScene: windowScene)
    created_window.rootViewController = controller
    created_window.makeKeyAndVisible()

    engine = created
    window = created_window
  }

  func sceneDidDisconnect(_ scene: UIScene) {
    engine?.destroyContext()
    engine = nil
    window = nil
  }

  /// Runs the app's generated plugin registrant against `engine`, if present.
  ///
  /// `GeneratedPluginRegistrant` belongs to the host app, so it is resolved by
  /// name. Without this the accessory engine would have no plugins at all,
  /// including this one.
  private static func registerPlugins(with engine: FlutterEngine) {
    guard let cls = NSClassFromString("GeneratedPluginRegistrant"),
      let meta = object_getClass(cls)
    else {
      return
    }
    let selector = NSSelectorFromString("registerWithRegistry:")
    guard class_respondsToSelector(meta, selector) else { return }
    _ = (cls as AnyObject).perform(selector, with: engine)
  }
}
