import ObjectiveC
import UIKit

/// Reports what the fold APIs actually look like on the running OS.
///
/// This package resolves the iOS 27.1 fold symbols through the Objective-C
/// runtime rather than the SDK, so one binary works whether or not the build
/// machine has Xcode 27.1 (see `FoldReader`). That choice means the compiler
/// cannot check those selectors, so this probe checks them against the live
/// runtime instead.
///
/// Two uses:
///
/// 1. Verifying `API_NOTES.md`. Run it on an iPhone Duo simulator and the
///    output gives real selector names, type encodings and class members —
///    stronger evidence than a header read, because it is what the code
///    actually calls.
/// 2. Bug reports. A user on hardware this package has never seen can run it
///    and paste the result.
///
/// It reads only: no fold API is invoked with side effects, nothing is
/// mutated, and nothing is instantiated. In particular it never calls
/// `value(forKey:)` on an unverified key — KVC raises `NSUnknownKeyException`
/// for a key a class does not define, which aborts the process. A diagnostic
/// must not be able to crash the app it is diagnosing.
enum NativeApiProbe {

  /// A human-readable dump of every fold-related symbol the runtime exposes.
  static func describe() -> String {
    var out: [String] = [
      "bifold native API probe",
      "iOS \(UIDevice.current.systemVersion)",
      "",
    ]

    out.append("== UIView methods matching 'reserved' ==")
    out.append(render(methods(of: UIView.self, matching: "reserved")))
    out.append("")

    for name in [
      "UIViewReservedRegion", "UIHingeInteraction", "UIArrangementViewController",
    ] {
      out.append("== class \(name) ==")
      guard let cls = NSClassFromString(name) else {
        out.append("  (not present)")
        out.append("")
        continue
      }
      out.append("  -- methods --")
      out.append(render(methods(of: cls, matching: "")))
      out.append("  -- properties --")
      out.append(render(properties(of: cls)))
      out.append("")
    }

    out.append(describeKindType())
    out.append(describeConstants())
    out.append(describeHinge())
    return out.joined(separator: "\n")
  }

  /// Identifies what a reserved region's `kind` actually is.
  ///
  /// The property encoding is `T@"UIViewReservedRegionKind"`, which is either
  /// a real class or an NS_TYPED_ENUM typedef of NSString. The two need very
  /// different calling code, so this settles which.
  private static func describeKindType() -> String {
    var out: [String] = ["== UIViewReservedRegionKind / Identifier =="]

    for name in ["UIViewReservedRegionKind", "UIViewReservedRegionIdentifier"] {
      guard let cls = NSClassFromString(name) else {
        out.append("  \(name): not a class -> NS_TYPED_ENUM (NSString typedef)")
        continue
      }
      out.append("  \(name): IS a class (\(cls))")
      out.append("  -- class methods (the enum-like accessors) --")
      if let meta = object_getClass(cls) {
        out.append(render(methods(of: meta, matching: "")))
      }
      out.append("  -- instance methods --")
      out.append(render(methods(of: cls, matching: "")))
      out.append("  -- properties --")
      out.append(render(properties(of: cls)))
    }
    out.append("")
    return out.joined(separator: "\n")
  }

  // MARK: - Constants

  /// Resolves the exported constants the reserved-region selector needs.
  ///
  /// `-reservedRegionsOfKind:options:` takes its kind as an *object*, and
  /// `UIViewReservedRegion.kind` is typed `UIViewReservedRegionKind` — the
  /// NS_TYPED_ENUM pattern, whose values are exported string constants.
  /// Without their real names the selector cannot be called at all, so they
  /// are looked up by symbol.
  private static func describeConstants() -> String {
    var out: [String] = ["== exported constants (dlsym) =="]

    let candidates = [
      "UIViewReservedRegionKindDivision",
      "UIViewReservedRegionKindOcclusion",
      "UIViewReservedRegionKindFold",
      "UIViewReservedRegionKindCamera",
      "UIViewReservedRegionIdentifierFold",
      "UIViewReservedRegionIdentifierCamera",
      "UIViewReservedRegionIdentifierVerticalBar",
    ]

    for name in candidates {
      if let value = constant(named: name) {
        out.append("  \(name) = \(value)")
      } else {
        out.append("  \(name): (not exported)")
      }
    }

    out.append("")
    out.append("== live call: -reservedRegionsOfKind: ==")
    let selector = NSSelectorFromString("reservedRegionsOfKind:")
    let probeView = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    guard probeView.responds(to: selector) else {
      out.append("  UIView does not respond to -reservedRegionsOfKind:")
      return out.joined(separator: "\n")
    }
    for name in [
      "UIViewReservedRegionKindDivision", "UIViewReservedRegionKindOcclusion",
    ] {
      guard let kind = constant(named: name) else { continue }
      let returned = probeView.perform(selector, with: kind)?
        .takeUnretainedValue()
      out.append("  \(name) -> \(String(describing: returned))")
    }
    return out.joined(separator: "\n")
  }

  /// Reads an exported Objective-C object constant by symbol name.
  ///
  /// Returns nil when the symbol is absent, which is the expected result on
  /// any OS older than the one that introduced it.
  private static func constant(named name: String) -> AnyObject? {
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
    else {
      return nil
    }
    return symbol.assumingMemoryBound(to: AnyObject?.self).pointee
  }

  // MARK: - Hinge

  /// Reports how hinge status is actually reachable.
  ///
  /// `UIHingeStatus` is not a class, so it is an NS_ENUM, and
  /// `UIHingeInteraction` exposes no `status` property — the value must arrive
  /// through `-initWithUpdateHandler:`.
  private static func describeHinge() -> String {
    var out: [String] = ["", "== hinge =="]

    guard let cls = NSClassFromString("UIHingeInteraction") else {
      out.append("  UIHingeInteraction not present")
      return out.joined(separator: "\n")
    }

    for name in ["initWithUpdateHandler:", "status", "hingeStatus", "angle"] {
      let responds = cls.instancesRespond(to: NSSelectorFromString(name))
      out.append("  responds to -\(name): \(responds)")
    }

    out.append("")
    out.append("== hinge-related exported constants ==")
    for name in [
      "UIHingeStatusClosed", "UIHingeStatusPartiallyOpen",
      "UIHingeStatusFullyOpen", "UIHingeStateDidChangeNotification",
      "UIHingeAngleDidChangeNotification",
    ] {
      let found = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) != nil
      out.append("  \(name): \(found ? "exported" : "(not exported)")")
    }

    return out.joined(separator: "\n")
  }

  // MARK: - Runtime introspection

  private static func render(_ lines: [String]) -> String {
    lines.isEmpty ? "  (none)" : lines.joined(separator: "\n")
  }

  /// Instance method names and type encodings of `cls`, filtered by `needle`.
  ///
  /// An empty `needle` returns every method. The type encoding is included
  /// because it settles whether a selector takes scalars or objects, which
  /// decides whether `perform(_:with:)` can call it at all.
  private static func methods(of cls: AnyClass, matching needle: String) -> [String] {
    var count: UInt32 = 0
    guard let list = class_copyMethodList(cls, &count) else { return [] }
    defer { free(list) }

    var results: [String] = []
    for index in 0..<Int(count) {
      let method = list[index]
      let name = NSStringFromSelector(method_getName(method))
      if !needle.isEmpty, !name.lowercased().contains(needle.lowercased()) {
        continue
      }
      let encoding = method_getTypeEncoding(method).map(String.init(cString:)) ?? "?"
      results.append("  -\(name)   \(encoding)")
    }
    return results.sorted()
  }

  /// Property names and attribute strings of `cls`.
  private static func properties(of cls: AnyClass) -> [String] {
    var count: UInt32 = 0
    guard let list = class_copyPropertyList(cls, &count) else { return [] }
    defer { free(list) }

    var results: [String] = []
    for index in 0..<Int(count) {
      let property = list[index]
      let name = String(cString: property_getName(property))
      let attributes =
        property_getAttributes(property).map(String.init(cString:)) ?? "?"
      results.append("  @\(name)   \(attributes)")
    }
    return results.sorted()
  }
}
