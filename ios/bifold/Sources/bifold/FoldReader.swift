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
/// The cost is that these selectors are not checked by the compiler. Every one
/// is listed in `API_NOTES.md`, and every call site that has not been verified
/// against the SDK headers is marked `UNVERIFIED` below.
///
/// # Verification status
///
/// At the time of writing no symbol here has been verified against the Xcode
/// 27.1 SDK, because that SDK was not installed. Run `scripts/verify-sdk.sh`
/// and reconcile with `API_NOTES.md` before shipping.
final class FoldReader {

  // MARK: - Symbol names

  // UNVERIFIED: every name in this block. Sourced from flutter/flutter#193025
  // and the `foldable` package, which agree with each other, not from Apple
  // documentation or SDK headers.
  private enum Symbol {
    /// UNVERIFIED: `-[UIView reservedRegionsOfKind:options:]`
    static let reservedRegions = NSSelectorFromString("reservedRegionsOfKind:options:")
    /// UNVERIFIED: `UIHingeInteraction`
    static let hingeInteraction = "UIHingeInteraction"
    /// UNVERIFIED: property `status` on the hinge interaction.
    static let hingeStatus = "status"
    /// UNVERIFIED: properties on a reserved region.
    static let regionFrame = "frame"
    static let regionMargins = "margins"
    static let regionIsActive = "isActive"
    static let regionKind = "kind"
  }

  /// UNVERIFIED: raw values of the reserved-region kind parameter.
  ///
  /// Apple documents the two kinds as "division" and "occlusion"; the integer
  /// values are a guess at a `NS_ENUM` starting at zero and must be confirmed.
  private enum RegionKindValue: Int {
    case division = 0
    case occlusion = 1
  }

  /// UNVERIFIED: option flag that includes regions which are not currently
  /// active. Most regions are inactive by default, so without this the reader
  /// would report almost nothing.
  private static let includeInactiveOption = 1

  /// Whether this OS exposes the fold APIs at all.
  ///
  /// False on every iOS before 27.1 and on every non-foldable device, which is
  /// what makes the whole package degrade rather than fail.
  static var isSupported: Bool {
    UIView.instancesRespond(to: Symbol.reservedRegions)
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
    guard FoldReader.isSupported else {
      return FoldReader.unsupportedPayload(version: version)
    }

    let regions = readRegions(from: view)
    return [
      "version": version,
      "isFoldable": true,
      "display": readDisplay(for: view),
      "pose": readPose(for: view),
      "regions": regions,
    ]
  }

  /// Which display the view is currently presented on.
  ///
  /// VERIFIED: `UIWindowScene.screen` is the documented replacement for
  /// `UIScreen.main`, which Apple deprecated for dual-display devices. Deciding
  /// *which* screen is the inner one is the unverified part: the heuristic is
  /// that the inner display is the larger of the two.
  private func readDisplay(for view: UIView) -> String {
    guard let scene = view.window?.windowScene else {
      return "none"
    }
    let screen = scene.screen
    let bounds = screen.bounds
    let longest = max(bounds.width, bounds.height)

    // UNVERIFIED heuristic. The outer display is materially smaller than the
    // inner one, but the threshold is not documented anywhere; it is a
    // midpoint between the two reported diagonals rather than a real boundary.
    // Replace this with a real signal if the SDK exposes one.
    return longest >= 800 ? "inner" : "outer"
  }

  /// How far the device is folded.
  ///
  /// UNVERIFIED throughout. Returns "unknown" when the hinge interaction
  /// cannot be resolved, which is the correct degraded answer.
  private func readPose(for view: UIView) -> String {
    guard let interaction = hingeInteraction(on: view) as? NSObject,
      let raw = interaction.value(forKey: Symbol.hingeStatus) as? Int
    else {
      return "unknown"
    }
    // UNVERIFIED: assumes `UIHingeStatus` is a three-case NS_ENUM in this
    // order. Confirm against the SDK before trusting.
    switch raw {
    case 0: return "closed"
    case 1: return "partiallyOpen"
    case 2: return "fullyOpen"
    default: return "unknown"
    }
  }

  /// Reads every reserved region, active or not.
  ///
  /// Regions are reported in the view's own coordinate space, in points. A
  /// UIKit point and a Flutter logical pixel are the same unit, so no scaling
  /// is applied when these cross the channel.
  ///
  /// UNVERIFIED: the coordinate space claim above. It is the natural reading
  /// of a method on `UIView`, but it has not been confirmed against the
  /// headers or observed in the simulator, and getting it wrong would place
  /// every region at the wrong offset.
  private func readRegions(from view: UIView) -> [[String: Any]] {
    var results: [[String: Any]] = []

    for kind in [RegionKindValue.division, RegionKindValue.occlusion] {
      for region in rawRegions(from: view, kind: kind) {
        guard let object = region as? NSObject else { continue }
        guard let frame = object.value(forKey: Symbol.regionFrame) as? CGRect
        else { continue }

        let margins =
          object.value(forKey: Symbol.regionMargins) as? UIEdgeInsets ?? .zero
        let isActive =
          object.value(forKey: Symbol.regionIsActive) as? Bool ?? false

        results.append([
          "kind": kind == .division ? "division" : "occlusion",
          "left": frame.minX,
          "top": frame.minY,
          "right": frame.maxX,
          "bottom": frame.maxY,
          "marginLeft": margins.left,
          "marginTop": margins.top,
          "marginRight": margins.right,
          "marginBottom": margins.bottom,
          "isActive": isActive,
        ])
      }
    }
    return results
  }

  /// Invokes the reserved-regions selector through the runtime.
  ///
  /// UNVERIFIED: the selector, its parameter types, and the option flag.
  private func rawRegions(from view: UIView, kind: RegionKindValue) -> [Any] {
    guard view.responds(to: Symbol.reservedRegions) else {
      return []
    }
    // `perform(_:with:with:)` boxes both arguments as objects. If the real
    // selector takes scalars this will not work and must be replaced with an
    // NSInvocation, which is why this is gated behind a cast check rather than
    // force-unwrapped.
    let result = view.perform(
      Symbol.reservedRegions,
      with: NSNumber(value: kind.rawValue),
      with: NSNumber(value: FoldReader.includeInactiveOption)
    )
    return result?.takeUnretainedValue() as? [Any] ?? []
  }

  /// Finds a hinge interaction already installed on the view, if any.
  private func hingeInteraction(on view: UIView) -> Any? {
    guard let type = NSClassFromString(Symbol.hingeInteraction) else {
      return nil
    }
    return view.interactions.first { object_getClass($0) == type || $0.isKind(of: type) }
  }

  // MARK: - Observing

  /// Calls `onChange` whenever the fold state may have changed.
  ///
  /// Regions arrive after the first layout pass and change as the device
  /// folds, so they must be observed rather than read once.
  ///
  /// The mechanism is deliberately boring: a zero-alpha sentinel subview that
  /// resizes with the Flutter view and reports its own `layoutSubviews`. That
  /// is ordinary, fully documented UIKit that works on every iOS version, and
  /// it fires on exactly the events that matter — the view resizing as the
  /// device folds, opens, or rotates. Relying on the hinge interaction's own
  /// callback would be more direct but its signature is unverified, and a
  /// missed callback means a layout that never updates.
  func observe(view: UIView, onChange: @escaping () -> Void) -> FoldObservation {
    let sentinel = LayoutSentinel(frame: view.bounds)
    sentinel.onLayout = onChange
    view.addSubview(sentinel)
    return FoldObservation(sentinel: sentinel)
  }
}

/// A cancellable fold-state observation.
final class FoldObservation {
  private weak var sentinel: LayoutSentinel?

  init(sentinel: LayoutSentinel) {
    self.sentinel = sentinel
  }

  func cancel() {
    sentinel?.onLayout = nil
    sentinel?.removeFromSuperview()
    sentinel = nil
  }
}

/// An invisible view that reports when its superview's size changes.
///
/// Non-interactive and zero-alpha, so it cannot affect the app it is watching.
final class LayoutSentinel: UIView {
  var onLayout: (() -> Void)?
  private var lastSize: CGSize = .zero

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
    onLayout?()
    lastSize = bounds.size
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil {
      onLayout?()
    }
  }
}
