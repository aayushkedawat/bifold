/// Counts how many times the capability answer has actually changed.
///
/// Dart rides its capability stream on the fold stream and re-queries
/// capabilities only when the `capabilityRevision` stamped on a fold payload
/// moves (`lib/src/method_channel_bifold.dart`). Without this, iOS queried once
/// -- at whatever the first payload said -- so a foldable that had not moved
/// yet stayed on `unknown` forever, which is exactly the "not yet known versus
/// proven absent" conflation the tri-state model exists to prevent.
///
/// The revision must move *only* when the answer changes. `CapabilityReader`
/// takes exactly two observed inputs -- whether a hinge and whether a division
/// have ever been seen, both sticky on the reader -- and every other input is a
/// static fact about the process. Bumping on anything more would make iOS
/// re-query capabilities at sensor rate, which is the cost the Dart-side gating
/// was added to avoid.
///
/// Extracted from the plugin so the rule is testable directly: `RunnerTests`
/// builds a plugin with no registrar, which can never drive a real capability
/// change end to end.
final class CapabilityRevisionTracker {

  /// The last input combination seen, or nil before the first call.
  private var lastSignature: String?

  /// The current revision counter.
  private(set) var revision = 0

  /// The revision for the capability inputs just observed, bumped if they
  /// differ from the previous ones.
  ///
  /// The first observation fixes the baseline without bumping: Dart starts
  /// below zero, so revision zero already forces the first query, and counting
  /// the baseline as a change would spend one round trip establishing what the
  /// first call would have fetched anyway.
  func revision(sawHinge: Bool, sawDivision: Bool) -> Int {
    let signature = "\(sawHinge ? 1 : 0)|\(sawDivision ? 1 : 0)"
    guard signature != lastSignature else { return revision }
    if lastSignature != nil {
      revision += 1
    }
    lastSignature = signature
    return revision
  }
}
