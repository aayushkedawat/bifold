import ObjectiveC
import UIKit

/// Asks UIKit where *it* would put two panes, and reports the answer.
///
/// `BifoldSplit` normally computes its own geometry from the reported division
/// region. That is predictable and testable, but it is this package's model of
/// the split rather than the system's. This oracle removes the guesswork: it
/// runs a real `UIArrangementViewController` with two empty children, lets
/// UIKit lay it out at a given size, and reads back the two frames. Flutter
/// then mirrors geometry the system itself produced.
///
/// # What it is not
///
/// The arrangement never renders anything and never receives input. Its
/// children are empty, non-interactive and hidden from accessibility. All real
/// content stays in Flutter. The controller exists only to be measured.
///
/// This is opt-in, because it does add a `UIViewController` to the host's
/// hierarchy — UIKit has to run genuine layout for the measurement to mean
/// anything, so the view cannot be hidden or zero-alpha.
///
/// # Verification
///
/// Verified against the iOS 27.1 SDK and confirmed reachable through the
/// Objective-C runtime on a booted iPhone Duo, 2026-09-20:
///
/// ```objc
/// // UIArrangementViewController.h
/// - (void)setViewController:(nullable UIViewController *)viewController
///               forPlacement:(UIArrangementViewControllerViewPlacement)placement;  // v32@0:8@16q24
/// - (nullable UIArrangementViewState *)stateForPlacement:(…)placement;             // @24@0:8q16
/// - (void)updateArrangement:(UIArrangement *)arrangement;
///
/// typedef NS_ENUM(NSInteger, UIArrangementViewControllerViewPlacement) {
///     …None = 0, …Primary = 1, …Secondary = 2
/// };
///
/// // UISplitArrangement (runtime): +splitArrangement, -setAxes: (v24@0:8Q16)
/// // UIUtilities/UIGeometry.h
/// typedef NS_OPTIONS(NSUInteger, UIAxis) {
///     UIAxisNeither = 0, UIAxisHorizontal = 1 << 0, UIAxisVertical = 1 << 1,
/// };
/// ```
@available(iOS 27.1, *)
final class ArrangementOracle {

  /// Placement values from `UIArrangementViewControllerViewPlacement`.
  private enum Placement {
    static let primary = 1
    static let secondary = 2
  }

  /// Values from `UIAxis`.
  enum Axis: UInt {
    case horizontal = 1
    case vertical = 2
  }

  private let controller: UIViewController
  private let primary = MeasurementPlaceholder()
  private let secondary = MeasurementPlaceholder()
  private weak var host: UIViewController?
  private var appliedAxis: Axis?

  /// Whether the OS exposes the arrangement API.
  static var isSupported: Bool {
    guard let cls = NSClassFromString("UIArrangementViewController") else {
      return false
    }
    return cls.instancesRespond(to: NSSelectorFromString("stateForPlacement:"))
      && NSClassFromString("UISplitArrangement") != nil
  }

  init?(host: UIViewController) {
    guard ArrangementOracle.isSupported,
      let cls = NSClassFromString("UIArrangementViewController") as? UIViewController.Type
    else {
      return nil
    }
    controller = cls.init(nibName: nil, bundle: nil)
    self.host = host

    setPlaceholder(primary, at: Placement.primary)
    setPlaceholder(secondary, at: Placement.secondary)

    host.addChild(controller)
    controller.view.backgroundColor = .clear
    controller.view.isUserInteractionEnabled = false
    controller.view.accessibilityElementsHidden = true
    // Deliberately not hidden and not zero-alpha: UIKit skips layout for those,
    // and a measurement of a view UIKit never laid out is worthless.
    host.view.addSubview(controller.view)
    controller.didMove(toParent: host)
  }

  /// Measures the two panes UIKit would produce in a box of `size`.
  ///
  /// Returns nil when the arrangement reports no state for either placement,
  /// which is how the system says "no split here".
  func measure(size: CGSize, axis: Axis) -> [String: Any]? {
    guard size.width > 0, size.height > 0 else { return nil }

    UIView.performWithoutAnimation {
      controller.view.frame = CGRect(origin: .zero, size: size)
      if appliedAxis != axis {
        appliedAxis = axis
        applySplitArrangement(axis: axis)
      }
      controller.view.setNeedsLayout()
      controller.view.layoutIfNeeded()
    }

    let primaryState = state(at: Placement.primary)
    let secondaryState = state(at: Placement.secondary)
    guard primaryState != nil || secondaryState != nil else { return nil }

    return [
      "primary": describe(primary, hasState: primaryState != nil),
      "secondary": describe(secondary, hasState: secondaryState != nil),
      "axis": axis == .horizontal ? "horizontal" : "vertical",
    ]
  }

  /// Removes the controller from the host.
  func detach() {
    controller.willMove(toParent: nil)
    controller.viewIfLoaded?.removeFromSuperview()
    controller.removeFromParent()
  }

  // MARK: - Runtime plumbing

  private func setPlaceholder(_ child: UIViewController, at placement: Int) {
    let selector = NSSelectorFromString("setViewController:forPlacement:")
    guard controller.responds(to: selector),
      let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "objc_msgSend")
    else { return }
    // Encoding v32@0:8@16q24 — object then NSInteger scalar, so perform() is
    // not usable here.
    typealias Call = @convention(c) (AnyObject, Selector, AnyObject, Int) -> Void
    unsafeBitCast(symbol, to: Call.self)(
      controller, selector, child, placement
    )
  }

  private func applySplitArrangement(axis: Axis) {
    guard let cls = NSClassFromString("UISplitArrangement"),
      let meta = object_getClass(cls),
      class_respondsToSelector(meta, NSSelectorFromString("splitArrangement")),
      let arrangement = (cls as AnyObject)
        .perform(NSSelectorFromString("splitArrangement"))?
        .takeUnretainedValue() as? NSObject
    else {
      return
    }

    // -setAxes: is v24@0:8Q16 — an NSUInteger scalar.
    if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "objc_msgSend") {
      typealias SetAxes = @convention(c) (AnyObject, Selector, UInt) -> Void
      unsafeBitCast(symbol, to: SetAxes.self)(
        arrangement, NSSelectorFromString("setAxes:"), axis.rawValue
      )
    }

    let update = NSSelectorFromString("updateArrangement:")
    if controller.responds(to: update) {
      _ = controller.perform(update, with: arrangement)
    }
  }

  private func state(at placement: Int) -> NSObject? {
    let selector = NSSelectorFromString("stateForPlacement:")
    guard controller.responds(to: selector),
      let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "objc_msgSend")
    else { return nil }
    // Encoding @24@0:8q16 — returns an object, takes an NSInteger.
    typealias Call = @convention(c) (AnyObject, Selector, Int) -> AnyObject?
    return unsafeBitCast(symbol, to: Call.self)(
      controller, selector, placement
    ) as? NSObject
  }

  /// Encodes one measured pane, in the arrangement's coordinate space.
  private func describe(
    _ child: UIViewController,
    hasState: Bool
  ) -> [String: Any] {
    guard hasState, let view = child.viewIfLoaded,
      view.isDescendant(of: controller.view)
    else {
      return ["left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0,
              "visible": false]
    }
    let frame = view.convert(view.bounds, to: controller.view)
    guard frame.width.isFinite, frame.height.isFinite,
      frame.width >= 0, frame.height >= 0
    else {
      return ["left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0,
              "visible": false]
    }
    let intersection = frame.intersection(controller.view.bounds)
    return [
      "left": frame.minX,
      "top": frame.minY,
      "right": frame.maxX,
      "bottom": frame.maxY,
      "visible": !frame.isEmpty && !intersection.isNull && !intersection.isEmpty,
    ]
  }
}

/// An empty, inert view controller used purely as something to measure.
@available(iOS 27.1, *)
private final class MeasurementPlaceholder: UIViewController {
  override func loadView() {
    let created = UIView()
    created.backgroundColor = .clear
    created.isUserInteractionEnabled = false
    created.accessibilityElementsHidden = true
    view = created
  }
}
