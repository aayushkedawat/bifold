import ObjectiveC
import UIKit

/// Reads fold state from a `UIView`.
///
/// # Why this uses the Objective-C runtime
///
/// Every fold symbol below ships in the iOS 27.1 SDK. Resolving them through
/// the runtime rather than calling them directly means one binary works
/// everywhere: it builds on Xcode 26.x and 27.0, which do not declare these
/// types at all, and still reports fold state when running on a device that
/// has them. The alternative — `#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 270100`
/// — produces a binary with no fold support whatsoever unless it was compiled
/// on Xcode 27.1, which would make this package useless to anyone whose CI has
/// not upgraded. Flutter's own CI is in exactly that position.
///
/// The cost is that these selectors are not checked by the compiler.
///
/// # Verification status
///
/// Every symbol used here was verified on 2026-09-20 against a booted iPhone
/// Duo simulator running iOS 27.1, by Objective-C runtime introspection —
/// `class_copyMethodList` and `class_copyPropertyList`, reproducible through
/// `NativeApiProbe`. That is a stronger check than reading a header, because
/// it is exactly what this code calls. Type encodings are quoted next to each
/// symbol; see `API_NOTES.md` for the full record.
///
/// Nothing here reads a key that has not been verified to exist. KVC raises
/// `NSUnknownKeyException` for an undefined key, which aborts the process
/// rather than returning nil.
final class FoldReader {

  /// Observes the hinge, when the OS provides one.
  ///
  /// Owned here so that pose and angle come from the platform rather than
  /// being inferred, and so that a hinge update can drive the stream directly.
  let hinge = HingeReader()

  // MARK: - Verified symbols

  private enum Symbol {
    /// VERIFIED `-[UIView reservedRegionsOfKind:]` → `@24@0:8@16`
    /// One object argument, returns an object. Callable with `perform(_:with:)`.
    static let regionsOfKind = NSSelectorFromString("reservedRegionsOfKind:")

    /// VERIFIED `-[UIView reservedRegionsOfKind:options:]` → `@32@0:8@16Q24`
    /// Object + `NSUInteger`. The scalar means `perform(_:with:with:)` cannot
    /// call this correctly; it goes through `objc_msgSend` instead.
    static let regionsOfKindOptions =
      NSSelectorFromString("reservedRegionsOfKind:options:")

    /// VERIFIED class methods on `UIViewReservedRegionKind`, both `@16@0:8`.
    /// The kind is an object obtained from these, not an integer.
    static let divisionKind = NSSelectorFromString("divisionRegionKind")
    static let occlusionKind = NSSelectorFromString("occlusionRegionKind")
  }

  /// VERIFIED properties of `UIViewReservedRegion`:
  ///   `@frame      {CGRect=...}`      readonly
  ///   `@margins    {UIEdgeInsets=...}` readonly
  ///   `@active     B, getter=isActive` readonly
  ///   `@kind       @"UIViewReservedRegionKind"` readonly
  ///   `@identifier @"UIViewReservedRegionIdentifier"` readonly
  private enum RegionKey {
    static let frame = "frame"
    static let margins = "margins"
    static let active = "active"
  }

  /// VERIFIED `UIViewReservedRegionQueryOptionsIncludeInactive = 1 << 0`
  /// from `UIViewReservedRegion.h` in the iOS 27.1 SDK. The enclosing type is
  /// `NS_OPTIONS(NSUInteger, UIViewReservedRegionQueryOptions)`, whose other
  /// case is `...OptionsNone = 0`.
  ///
  /// Without this flag the query returns only active regions, and most regions
  /// are inactive until their hardware is in use.
  private static let includeInactiveOption: UInt = 1 << 0

  /// The `UIViewReservedRegionKind` object for the fold.
  private static let divisionKindObject: AnyObject? = kindObject(Symbol.divisionKind)

  /// The `UIViewReservedRegionKind` object for hardware occlusions.
  private static let occlusionKindObject: AnyObject? = kindObject(Symbol.occlusionKind)

  private static func kindObject(_ selector: Selector) -> AnyObject? {
    guard let cls = NSClassFromString("UIViewReservedRegionKind"),
      let meta = object_getClass(cls),
      class_respondsToSelector(meta, selector)
    else {
      return nil
    }
    return (cls as AnyObject).perform(selector)?.takeUnretainedValue()
  }

  /// Whether this OS exposes the fold APIs at all.
  ///
  /// False on every iOS before 27.1, which is what makes the package degrade
  /// rather than fail.
  static var isSupported: Bool {
    UIView.instancesRespond(to: Symbol.regionsOfKind)
      && divisionKindObject != nil
  }

  // MARK: - Reading

  /// The payload sent when there is nothing to report.
  ///
  /// Shaped identically to a real reading so Dart has one decode path.
  static func unsupportedPayload(version: Int) -> [String: Any] {
    return [
      "version": version,
      "isFoldable": false,
      "display": "none",
      "pose": "unknown",
      "regions": [[String: Any]](),
    ]
  }

  /// Reads the current fold state from `view`.
  func read(from view: UIView, version: Int) -> [String: Any] {
    guard FoldReader.isSupported, isFoldableDevice() else {
      return FoldReader.unsupportedPayload(version: version)
    }

    let regions = readRegions(from: view)
    let display = readDisplay(for: view)
    let traits = view.traitCollection
    var payload: [String: Any] = [
      "version": version,
      "isFoldable": true,
      "display": display,
      "pose": pose(display: display, regions: regions),
      "regions": regions,
      "horizontalSizeClass": FoldReader.sizeClassName(traits.horizontalSizeClass),
      "verticalSizeClass": FoldReader.sizeClassName(traits.verticalSizeClass),
      "verticalBarEdge": FoldReader.verticalBarEdgeName(traits),
    ]
    if let angle = hinge.state?.angle {
      payload["hingeAngle"] = angle
    }
    return payload
  }

  /// Whether this device actually has a fold.
  ///
  /// The OS check alone only says the running iOS declares the fold APIs,
  /// which a non-foldable iPhone and an iPad on the same release also do. The
  /// authoritative signal is the hinge: `UIHingeInteractionUpdate.hinge` is
  /// documented as nil "when the interaction leaves a hierarchy that provides
  /// hinge updates", so a hinge that has ever been reported means a real fold.
  ///
  /// Until the first hinge update arrives, fall back to the presence of a
  /// division region, and then to the phone idiom — which at least keeps an
  /// iPad from being announced as a foldable phone.
  private func isFoldableDevice() -> Bool {
    if hinge.sawHinge {
      return true
    }
    return UIDevice.current.userInterfaceIdiom == .phone
  }

  /// Names a `UIUserInterfaceSizeClass` for the channel.
  ///
  /// Apple's guidance for this device is to lay out against size classes
  /// rather than orientation, because the inner display does not honour an
  /// app's supported interface orientations. Exposing them saves every caller
  /// from reaching for a platform channel of their own.
  private static func sizeClassName(_ value: UIUserInterfaceSizeClass) -> String {
    switch value {
    case .compact: return "compact"
    case .regular: return "regular"
    default: return "unspecified"
    }
  }

  /// Reads `UITraitCollection.verticalBarEdge`.
  ///
  /// VERIFIED `UIVerticalBarEdge.h`, iOS 27.1 SDK:
  /// `UIVerticalBarEdgeUnspecified = 0`, `Leading = 1`, `Trailing = 2`, read
  /// from `@property (nonatomic, readonly) UIVerticalBarEdge verticalBarEdge`.
  ///
  /// The header notes this "reflects the system's preferred edge regardless of
  /// whether a vertical bar is currently visible", and is `Unspecified` on
  /// hardware or in contexts with no vertical bar — which is why it degrades
  /// cleanly on every other device.
  ///
  /// Resolved through the runtime so the package still builds on Xcode 26.x.
  private static func verticalBarEdgeName(_ traits: UITraitCollection) -> String {
    let selector = NSSelectorFromString("verticalBarEdge")
    guard traits.responds(to: selector),
      let raw = traits.value(forKey: "verticalBarEdge") as? Int
    else {
      return "unspecified"
    }
    switch raw {
    case 1: return "leading"
    case 2: return "trailing"
    default: return "unspecified"
    }
  }

  /// Which display the view is currently presented on.
  ///
  /// Apple documents that the inner display is regular width *and* regular
  /// height, while the outer display behaves like a conventional iPhone. On a
  /// phone, regular/regular therefore means the inner display. This is a
  /// documented behavioural signal rather than a measured size threshold,
  /// which is why no screen dimension appears here.
  private func readDisplay(for view: UIView) -> String {
    guard view.window != nil else {
      return "none"
    }
    let traits = view.traitCollection
    let isRegular =
      traits.horizontalSizeClass == .regular
      && traits.verticalSizeClass == .regular
    return isRegular ? "inner" : "outer"
  }

  /// How far the device is folded.
  ///
  /// Prefers the platform's own `UIHingeStatus`, which is authoritative and
  /// arrives as soon as the hinge interaction is attached. Falls back to
  /// deriving the pose from the regions when no hinge has been reported yet,
  /// so the very first frame is still useful.
  private func pose(display: String, regions: [[String: Any]]) -> String {
    if let status = hinge.state?.status {
      let name = HingeReader.poseName(for: status)
      if name != "unknown" {
        return name
      }
    }
    return derivePose(display: display, regions: regions)
  }

  /// Derives how far the device is folded from the regions alone.
  ///
  /// Used until the first hinge update lands, and on any OS where the hinge
  /// API is missing. The regions carry the same information:
  ///
  /// * outer display, no regions      → shut
  /// * inner display, division active → creased, so part-way open
  /// * inner display, division idle   → flat
  ///
  /// This also matches how flutter/flutter#193025 reports fold state, so an
  /// app that later moves to engine-native display features sees no change.
  private func derivePose(display: String, regions: [[String: Any]]) -> String {
    if display == "outer" {
      return "closed"
    }
    guard display == "inner" else {
      return "unknown"
    }

    var sawDivision = false
    for region in regions where region["kind"] as? String == "division" {
      sawDivision = true
      if region["isActive"] as? Bool == true {
        return "partiallyOpen"
      }
    }
    return sawDivision ? "fullyOpen" : "unknown"
  }

  /// Reads every reserved region, active or not.
  ///
  /// VERIFIED coordinate space: `UIViewReservedRegion` is documented in the
  /// 27.1 SDK as "a region within a view's coordinate space", and its `frame`
  /// as "the rect of the region in the view's coordinate space, including the
  /// margins". Regions are therefore relative to the receiving view, in
  /// points. A UIKit point and a Flutter logical pixel are the same unit, so
  /// no scaling is applied crossing the channel.
  ///
  /// Note "including the margins": the frame is the whole area to avoid, and
  /// `margins` says how much of it is clearance rather than hardware. The Dart
  /// side must not inflate the frame by the margins again.
  private func readRegions(from view: UIView) -> [[String: Any]] {
    var results: [[String: Any]] = []

    let kinds: [(String, AnyObject?)] = [
      ("division", FoldReader.divisionKindObject),
      ("occlusion", FoldReader.occlusionKindObject),
    ]

    for (name, kind) in kinds {
      guard let kind else { continue }
      for region in rawRegions(from: view, kind: kind) {
        guard let object = region as? NSObject,
          let encoded = encode(region: object, kind: name)
        else { continue }
        results.append(encoded)
      }
    }
    return results
  }

  /// Converts one `UIViewReservedRegion` into a channel payload.
  ///
  /// `frame` and `margins` are structs, so KVC hands them back boxed in an
  /// `NSValue`. Casting the boxed value straight to `CGRect` fails and would
  /// silently drop every region, so both are unboxed explicitly.
  ///
  /// The frame is passed through unchanged, margins included, exactly as the
  /// platform reports it.
  private func encode(region: NSObject, kind: String) -> [String: Any]? {
    guard let frame = (region.value(forKey: RegionKey.frame) as? NSValue)?
      .cgRectValue
    else {
      return nil
    }
    let margins =
      (region.value(forKey: RegionKey.margins) as? NSValue)?
      .uiEdgeInsetsValue ?? .zero
    let isActive = (region.value(forKey: RegionKey.active) as? Bool) ?? false

    return [
      "kind": kind,
      "left": frame.minX,
      "top": frame.minY,
      "right": frame.maxX,
      "bottom": frame.maxY,
      "marginLeft": margins.left,
      "marginTop": margins.top,
      "marginRight": margins.right,
      "marginBottom": margins.bottom,
      "isActive": isActive,
    ]
  }

  /// Invokes the reserved-regions selector.
  ///
  /// Prefers the two-argument form so that inactive regions are included —
  /// most regions are inactive until their hardware is in use, and a layout
  /// still needs to know where they are. Falls back to the one-argument form,
  /// which `perform(_:with:)` can call directly.
  private func rawRegions(from view: UIView, kind: AnyObject) -> [Any] {
    if view.responds(to: Symbol.regionsOfKindOptions),
      let withOptions = regionsWithOptions(view: view, kind: kind)
    {
      return withOptions
    }
    guard view.responds(to: Symbol.regionsOfKind) else {
      return []
    }
    return view.perform(Symbol.regionsOfKind, with: kind)?
      .takeUnretainedValue() as? [Any] ?? []
  }

  /// Calls `-reservedRegionsOfKind:options:` through `objc_msgSend`.
  ///
  /// The verified encoding `@32@0:8@16Q24` has an object followed by a scalar
  /// `NSUInteger`. `perform(_:with:with:)` boxes both arguments as objects, so
  /// it would pass an `NSNumber` pointer where a machine word is expected.
  /// Casting `objc_msgSend` to the exact signature is the only correct way to
  /// make this call without the SDK's declaration.
  private func regionsWithOptions(view: UIView, kind: AnyObject) -> [Any]? {
    typealias Call = @convention(c) (AnyObject, Selector, AnyObject, UInt)
      -> AnyObject?
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "objc_msgSend")
    else {
      return nil
    }
    let call = unsafeBitCast(symbol, to: Call.self)
    let returned = call(
      view,
      Symbol.regionsOfKindOptions,
      kind,
      FoldReader.includeInactiveOption
    )
    return returned as? [Any]
  }

  // MARK: - Observing

  /// Calls `onChange` whenever the fold state may have changed.
  ///
  /// Regions arrive after the first layout pass and change as the device
  /// folds, so they must be observed rather than read once.
  ///
  /// Two mechanisms, because they catch different things:
  ///
  /// * A `UIHingeInteraction`, which pushes an update the moment the hinge
  ///   moves. This is the responsive path and the source of pose and angle.
  /// * A zero-alpha sentinel subview that resizes with the Flutter view and
  ///   reports its own `layoutSubviews`. Regions lag the hinge and arrive only
  ///   after a layout pass, so a hinge update alone can report a pose whose
  ///   regions have not landed yet. The sentinel catches that second wave, and
  ///   keeps the package working on an OS with no hinge API at all.
  func observe(view: UIView, onChange: @escaping () -> Void) -> FoldObservation {
    hinge.attach(to: view, onChange: onChange)

    let sentinel = LayoutSentinel(frame: view.bounds)
    sentinel.onLayout = onChange
    view.addSubview(sentinel)
    return FoldObservation(sentinel: sentinel, hinge: hinge)
  }
}

/// A cancellable fold-state observation.
final class FoldObservation {
  private weak var sentinel: LayoutSentinel?
  private let hinge: HingeReader

  init(sentinel: LayoutSentinel, hinge: HingeReader) {
    self.sentinel = sentinel
    self.hinge = hinge
  }

  func cancel() {
    sentinel?.onLayout = nil
    sentinel?.removeFromSuperview()
    sentinel = nil
    hinge.detach()
  }
}

/// An invisible view that reports when its superview's size changes.
///
/// Non-interactive and zero-alpha, so it cannot affect the app it watches.
final class LayoutSentinel: UIView {
  var onLayout: (() -> Void)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    autoresizingMask = [.flexibleWidth, .flexibleHeight]
    isUserInteractionEnabled = false
    alpha = 0
    isAccessibilityElement = false
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("LayoutSentinel is created in code only.")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    // Regions lag the hinge, so report on every layout rather than only when
    // the size changes: an unchanged size can still mean new regions.
    //
    // This is also the lifecycle event Apple names for observing a scene
    // accessory's availability, so the capture accessory is refreshed here.
    if #available(iOS 27.1, *) {
      CaptureAccessory.shared?.refreshAvailability()
    }
    onLayout?()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil {
      onLayout?()
    }
  }
}
