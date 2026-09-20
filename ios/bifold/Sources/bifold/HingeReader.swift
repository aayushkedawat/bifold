import ObjectiveC
import UIKit

/// The hinge state reported by the platform.
struct HingeState {
  /// Raw `UIHingeStatus`. See `HingeReader.poseName(for:)`.
  let status: Int
  /// Hinge angle in radians, or nil when the platform reports none.
  let angle: Double?
}

/// Observes the device hinge through `UIHingeInteraction`.
///
/// # Verification
///
/// Verified against `UIHingeInteraction.h` and `UIHinge.h` in the iOS 27.1
/// SDK on 2026-09-20. The exact declarations this depends on:
///
/// ```objc
/// // UIHingeInteraction.h
/// - (instancetype)initWithUpdateHandler:
///     (void(^)(UIHingeInteraction *, UIHingeInteractionUpdate *))updateHandler;
/// @property (nonatomic, readonly, copy, nullable) UIHinge *hinge;  // on the update
///
/// // UIHinge.h
/// typedef NS_ENUM(NSInteger, UIHingeStatus) {
///     UIHingeStatusUnknown = 0,
///     UIHingeStatusClosed = 1,
///     UIHingeStatusPartiallyOpen = 2,
///     UIHingeStatusFullyOpen = 3,
/// };
/// @property (nonatomic, readonly) UIHingeStatus status;
/// @property (nonatomic, readonly) CGFloat angle;  // radians
/// ```
///
/// Note the enum starts at `Unknown = 0`, so `Closed` is 1, not 0. An earlier
/// draft of this package guessed a zero-based `closed/partiallyOpen/fullyOpen`
/// ordering, which would have reported every pose shifted by one.
///
/// Symbols are still resolved through the Objective-C runtime rather than the
/// SDK, so the package keeps building on Xcode 26.x and 27.0. See `FoldReader`.
final class HingeReader {

  /// The most recent state the platform reported, or nil if none yet.
  ///
  /// `UIHingeInteractionUpdate.hinge` is documented as nil "when the
  /// interaction leaves a hierarchy that provides hinge updates", so nil here
  /// genuinely means "no hinge", not merely "not yet observed".
  private(set) var state: HingeState?

  /// Whether the platform has ever reported a hinge for this view.
  ///
  /// This is a far better foldable test than a device-idiom guess: only a
  /// hierarchy that actually provides hinge updates produces a non-nil hinge.
  private(set) var sawHinge = false

  private var interaction: NSObject?
  private weak var view: UIView?

  /// Whether this OS exposes the hinge API at all.
  static var isSupported: Bool {
    NSClassFromString("UIHingeInteraction") != nil
  }

  /// Maps a raw `UIHingeStatus` onto the pose names the Dart side decodes.
  static func poseName(for status: Int) -> String {
    switch status {
    case 1: return "closed"
    case 2: return "partiallyOpen"
    case 3: return "fullyOpen"
    default: return "unknown"  // UIHingeStatusUnknown == 0
    }
  }

  /// Starts observing the hinge on `view`.
  ///
  /// `onChange` fires on every hinge update, which is what makes fold state
  /// push-based rather than inferred from a resize.
  func attach(to view: UIView, onChange: @escaping () -> Void) {
    guard HingeReader.isSupported, interaction == nil else { return }
    guard let cls = NSClassFromString("UIHingeInteraction") else { return }

    // The block's signature is (UIHingeInteraction *, UIHingeInteractionUpdate *).
    let handler: @convention(block) (AnyObject?, AnyObject?) -> Void = {
      [weak self] _, update in
      self?.absorb(update: update)
      onChange()
    }

    guard let created = HingeReader.makeInteraction(cls: cls, handler: handler)
    else {
      return
    }
    interaction = created
    self.view = view

    // UIHingeInteraction conforms to UIInteraction; addInteraction takes that
    // protocol, so the cast is what lets a runtime-created object be added.
    if let asInteraction = created as? UIInteraction {
      view.addInteraction(asInteraction)
    }
  }

  /// Stops observing.
  func detach() {
    if let interaction = interaction as? UIInteraction {
      view?.removeInteraction(interaction)
    }
    interaction = nil
    view = nil
    state = nil
  }

  /// Reads the hinge out of an update object.
  ///
  /// Both keys are verified properties, so KVC cannot raise here. `hinge` is
  /// explicitly nullable, and nil is meaningful: the view left a hierarchy
  /// that provides hinge updates.
  private func absorb(update: AnyObject?) {
    guard let update = update as? NSObject,
      let hinge = update.value(forKey: "hinge") as? NSObject
    else {
      state = nil
      return
    }
    sawHinge = true
    let status = (hinge.value(forKey: "status") as? Int) ?? 0
    let angle = hinge.value(forKey: "angle") as? Double
    state = HingeState(status: status, angle: angle)
  }

  /// Allocates and initialises a `UIHingeInteraction` through the runtime.
  ///
  /// `UIHingeInteraction` marks `init` and `new` unavailable, so
  /// `initWithUpdateHandler:` is the only way in. Ownership is handled
  /// explicitly: `alloc` returns a +1 object and `init…` consumes and returns
  /// it, so the result is taken as retained exactly once. Letting Swift infer
  /// this from an `AnyObject` return would over-retain, because the compiler
  /// cannot see the selector family behind a function pointer.
  private static func makeInteraction(
    cls: AnyClass,
    handler: Any
  ) -> NSObject? {
    typealias AllocCall = @convention(c) (AnyClass, Selector)
      -> Unmanaged<AnyObject>?
    typealias InitCall = @convention(c) (AnyObject, Selector, Any)
      -> Unmanaged<AnyObject>?

    guard
      let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "objc_msgSend")
    else {
      return nil
    }

    let allocate = unsafeBitCast(symbol, to: AllocCall.self)
    guard
      let allocated = allocate(cls, NSSelectorFromString("alloc"))?
        .takeUnretainedValue()
    else {
      return nil
    }

    let initialise = unsafeBitCast(symbol, to: InitCall.self)
    guard
      let created = initialise(
        allocated,
        NSSelectorFromString("initWithUpdateHandler:"),
        handler
      )?.takeRetainedValue() as? NSObject
    else {
      return nil
    }
    return created
  }
}
