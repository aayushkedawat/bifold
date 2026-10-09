import UIKit

/// Answers what this device *can* do, as opposed to what it is doing.
///
/// The rules, which the Dart resolver then enforces across reports:
///
/// * Only an authoritative static query may say `unsupported`. Never having
///   observed something is not evidence that it is absent.
/// * An observation may only ever move a capability up to `supported`.
/// * Anything else is `unknown`, which is an answer rather than a failure.
enum CapabilityReader {

  private static func evidence(_ status: String, _ source: String) -> [String: Any] {
    ["status": status, "source": source]
  }

  private static let unknownNotObserved = evidence("unknown", "ios.not_yet_observed")

  /// What this build knows about the running device.
  ///
  /// - Parameters:
  ///   - sawHinge: whether a hinge has been observed in this process. Sticky
  ///     on the reader side; passed in rather than read here so that this type
  ///     stays a pure function of its inputs.
  ///   - sawDivision: whether a division region has ever been reported.
  /// Whether the capture accessory exists on the running OS.
  ///
  /// Behind an availability check so that one binary still builds against an
  /// older SDK and runs on an older OS, which is the same rule the rest of the
  /// plugin follows.
  private static var captureAccessorySupported: Bool {
    if #available(iOS 27.1, *) {
      return CaptureAccessory.isSupported
    }
    return false
  }

  static func payload(sawHinge: Bool, sawDivision: Bool) -> [String: Any] {
    // The fold symbols either exist in this OS or they do not, and that is a
    // static fact about the running system rather than an observation.
    let osHasFoldApi = FoldReader.isSupported
    let osHasHingeApi = HingeReader.isSupported

    let fold: [String: Any]
    if sawHinge {
      fold = evidence("supported", "ios.UIHingeInteraction.observed")
    } else if !osHasFoldApi {
      // No fold API in this OS at all: nothing here can ever fold.
      fold = evidence("unsupported", "ios.fold_api_absent")
    } else if UIDevice.current.userInterfaceIdiom != .phone {
      // iPad and the rest are not the foldable device, and the fold APIs are
      // not going to make them one.
      fold = evidence("unsupported", "ios.not_phone_idiom")
    } else {
      // A foldable iPhone that has not moved yet looks exactly like an
      // ordinary iPhone. Saying "no" here would be a guess.
      fold = evidence("unknown", "ios.fold_api_present_but_unobserved")
    }

    let hinge: [String: Any] =
      osHasHingeApi
      ? (sawHinge
        ? evidence("supported", "ios.UIHingeInteraction.observed")
        : evidence("unknown", "ios.UIHingeInteraction.present_unobserved"))
      : evidence("unsupported", "ios.hinge_api_absent")

    // Anything that needs a fold to exist cannot be more certain than the
    // fold itself. Keyed off symbol presence alone, the three capabilities
    // below claimed a cover display, a half-open posture and reserved regions
    // on an ordinary non-foldable iPhone running a release that merely *has*
    // the fold APIs -- and contradicted themselves on iPad, reporting
    // `fold: unsupported` beside `coverDisplay: supported`, which is not a
    // state that exists. `hasCoverDisplay` is exactly what an app branches on
    // to build cover-display UI, so a false positive there is expensive.
    let foldStatus = fold["status"] as? String ?? "unknown"

    /// Downgrades an OS-level answer by what is known about the fold.
    ///
    /// A capability cannot be `supported` on a device that has not been shown
    /// to fold, and it is `unsupported` once the fold is ruled out.
    func gatedByFold(_ osAnswer: [String: Any]) -> [String: Any] {
      switch foldStatus {
      case "supported":
        return osAnswer
      case "unsupported":
        // No fold on this device, so nothing that depends on one exists.
        return evidence("unsupported", "ios.no_fold_on_this_device")
      default:
        // The OS can do it; whether this device folds is still unestablished.
        return evidence("unknown", "ios.fold_unobserved")
      }
    }

    return [
      "version": 1,
      // Brief decision 4: platform belongs in `raw` and the diagnostic
      // report, never as a typed getter on BifoldCapabilities.
      "platform": "ios",
      "isResolved": true,
      // Fold orientation is not reported on this platform, and the one shape
      // it could be is not worth asserting from an absence.
      "formFactor": sawHinge ? "book" : "unknown",
      "rearDisplayModes": captureAccessorySupported ? ["presentation"] : [],
      "features": [
        "fold": fold,
        "hingeAngle": hinge,
        // The platform reports a part-way-open pose, so the capability is a
        // property of the OS rather than something to wait and observe.
        // The platform reports a part-way-open pose, so on a device that
        // folds this is a property of the OS rather than something to observe
        // -- but it still needs the device to fold.
        "halfOpenedPosture": osHasHingeApi
          ? gatedByFold(evidence("supported", "ios.UIHingeStatus.partiallyOpen"))
          : evidence("unsupported", "ios.hinge_api_absent"),
        "rearDisplay": captureAccessorySupported
          ? gatedByFold(evidence("supported", "ios.captureAccessory"))
          : evidence("unsupported", "ios.capture_accessory_absent"),
        // The app runs on the outer display when the device is shut. That is
        // how the platform behaves, not something to be queried -- on a
        // device that has an outer display to run on.
        "coverDisplay": osHasFoldApi
          ? gatedByFold(evidence("supported", "ios.outer_display"))
          : evidence("unsupported", "ios.fold_api_absent"),
        "reservedRegions": osHasFoldApi
          ? gatedByFold(evidence("supported", "ios.UIViewReservedRegion"))
          : evidence("unsupported", "ios.fold_api_absent"),
        "separatingFold": sawDivision
          ? evidence("supported", "ios.division_region.observed")
          : unknownNotObserved,
        // The fold on this device creases rather than occludes: content
        // remains visible across it. Nothing has been seen to suggest
        // otherwise, so this stays unobserved rather than claimed either way.
        "foldOcclusion": unknownNotObserved,
      ],
    ]
  }
}
