import Flutter
import UIKit
import XCTest

@testable import bifold

/// Tests the plugin's method channel against the real native implementation.
///
/// This file replaces the untouched Flutter template, which called
/// `getPlatformVersion` — a method this plugin does not implement — and then
/// force-cast the `FlutterMethodNotImplemented` result to `String`. It would
/// have crashed the moment anything ran it, and nothing ever did.
///
/// These run on any simulator. They deliberately assert the *shape* of each
/// payload rather than fold values, because no simulator other than an iPhone
/// Duo reports a fold, and a test that needed one could never run here.
class RunnerTests: XCTestCase {

  /// Calls `handle` and returns the result the plugin produced.
  private func call(
    _ method: String,
    arguments: Any? = nil,
    in plugin: BifoldPlugin
  ) -> Any? {
    var captured: Any?
    let finished = expectation(description: method)
    plugin.handle(
      FlutterMethodCall(methodName: method, arguments: arguments),
      result: { value in
        captured = value
        finished.fulfill()
      }
    )
    wait(for: [finished], timeout: 5)
    return captured
  }

  private func makePlugin() -> BifoldPlugin {
    // No registrar: the plugin must answer every method without a host view,
    // because that is the state it is in during app launch.
    return BifoldPlugin(registrar: nil)
  }

  func testGetFoldInfoAnswersWithoutAView() throws {
    let payload = try XCTUnwrap(
      call("getFoldInfo", in: makePlugin()) as? [String: Any],
      "getFoldInfo must answer with a payload, never a FlutterError: a view "
        + "that has not loaded yet is a normal startup race, not a failure"
    )

    XCTAssertEqual(payload["isFoldable"] as? Bool, false)
    XCTAssertEqual(payload["version"] as? Int, 1)

    // Dart reads isResolved strictly, so it must be present. False here is the
    // point: nothing has been established, which is different from proving
    // the device has no fold.
    let resolved = try XCTUnwrap(
      payload["isResolved"] as? Bool,
      "Dart reads isResolved with == true, so an omitted key silently means "
        + "'nothing established' forever"
    )
    XCTAssertFalse(resolved)

    XCTAssertNotNil(
      payload["capabilityRevision"] as? Int,
      "the capability stream re-queries on this key; without it Dart falls "
        + "back to a constant and never sees a capability change"
    )
  }

  func testGetCapabilitiesReportsEveryFeature() throws {
    let payload = try XCTUnwrap(
      call("getCapabilities", in: makePlugin()) as? [String: Any]
    )

    XCTAssertEqual(payload["platform"] as? String, "ios")
    XCTAssertEqual(payload["version"] as? Int, 1)
    XCTAssertEqual(payload["isResolved"] as? Bool, true)
    XCTAssertNotNil(payload["formFactor"] as? String)
    XCTAssertNotNil(payload["rearDisplayModes"] as? [String])

    let features = try XCTUnwrap(payload["features"] as? [String: Any])
    // These spellings are the wire contract: they are `FoldFeature`'s own
    // enum names, and Dart drops anything it does not recognise.
    for feature in [
      "fold", "hingeAngle", "halfOpenedPosture", "rearDisplay",
      "coverDisplay", "reservedRegions", "separatingFold", "foldOcclusion",
    ] {
      let evidence = try XCTUnwrap(
        features[feature] as? [String: Any],
        "\(feature) is missing from the capability payload"
      )
      let status = try XCTUnwrap(evidence["status"] as? String)
      XCTAssertTrue(
        ["supported", "unsupported", "unknown"].contains(status),
        "\(feature) reported an unrecognised status: \(status)"
      )
    }
  }

  func testCapabilitiesNeverContradictTheFold() throws {
    let payload = try XCTUnwrap(
      call("getCapabilities", in: makePlugin()) as? [String: Any]
    )
    let features = try XCTUnwrap(payload["features"] as? [String: Any])

    func status(_ name: String) throws -> String {
      let evidence = try XCTUnwrap(features[name] as? [String: Any])
      return try XCTUnwrap(evidence["status"] as? String)
    }

    // Nothing that needs a fold may claim support on a device whose fold is
    // not established. This simulator is not a foldable, so these used to
    // report `supported` purely because the OS declares the symbols — and on
    // iPad produced `fold: unsupported` beside `coverDisplay: supported`.
    if try status("fold") != "supported" {
      for dependent in ["coverDisplay", "halfOpenedPosture", "reservedRegions"] {
        XCTAssertNotEqual(
          try status(dependent),
          "supported",
          "\(dependent) claimed support while the fold itself did not"
        )
      }
    }
  }

  func testRearDisplayStatusIsAlwaysAnswerable() throws {
    let payload = try XCTUnwrap(
      call("rearDisplayStatus", in: makePlugin()) as? [String: Any]
    )
    for mode in ["presentation", "transfer"] {
      let value = try XCTUnwrap(payload[mode] as? String)
      XCTAssertTrue(
        ["unsupported", "unavailable", "available", "active"].contains(value),
        "\(mode) reported an unrecognised status: \(value)"
      )
    }
    // iOS has no equivalent of moving the whole app across, and saying so is
    // better than pretending.
    XCTAssertEqual(payload["transfer"] as? String, "unsupported")
  }

  func testUnknownMethodIsNotImplementedRatherThanACrash() {
    let result = call("thisMethodDoesNotExist", in: makePlugin())
    // FlutterMethodNotImplemented is a sentinel *instance*, not a type, so
    // this is an identity check rather than an `is` test.
    XCTAssertTrue(
      (result as AnyObject) === (FlutterMethodNotImplemented as AnyObject),
      "an unknown method must be reported as not implemented"
    )
  }

  func testDiagnosticReportNamesWhatItCouldNotResolve() throws {
    let report = try XCTUnwrap(
      call("debugDescribeNativeApi", in: makePlugin()) as? String
    )
    XCTAssertTrue(report.contains("bifold native API probe"))
    // The verdict is the mitigation for runtime symbol resolution failing
    // silently, so it has to be in the report a user would paste.
    XCTAssertTrue(
      report.contains("== symbol resolution =="),
      "the report must state whether the fold symbols resolved"
    )
  }
}
