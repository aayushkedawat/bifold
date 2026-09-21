import 'dart:ui' show Size;
import 'package:bifold/bifold.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BifoldCapabilities', () {
    test('unresolved knows nothing and says so', () {
      const caps = BifoldCapabilities.unresolved;
      expect(caps.isResolved, isFalse);
      for (final feature in FoldFeature.values) {
        expect(caps.statusOf(feature), CapabilityStatus.unknown);
      }
      // The trap this type exists to avoid: a false hasX that looks like "no".
      expect(caps.hasFold, isFalse);
      expect(
          caps.statusOf(FoldFeature.fold), isNot(CapabilityStatus.unsupported));
    });

    test('none is resolved and negative about everything', () {
      const caps = BifoldCapabilities.none;
      expect(caps.isResolved, isTrue);
      expect(caps.formFactor, FoldFormFactor.none);
      for (final feature in FoldFeature.values) {
        expect(caps.statusOf(feature), CapabilityStatus.unsupported);
      }
    });

    test('unresolved and none are different answers', () {
      // Both report hasFold false. Only one of them means "no".
      expect(BifoldCapabilities.unresolved.hasFold, isFalse);
      expect(BifoldCapabilities.none.hasFold, isFalse);
      expect(BifoldCapabilities.unresolved, isNot(BifoldCapabilities.none));
    });

    test('decodes a platform payload, and keeps the source', () {
      final caps = BifoldCapabilities.fromMap(<Object?, Object?>{
        'isResolved': true,
        'formFactor': 'book',
        'rearDisplayModes': <Object?>['presentation', 'transfer'],
        'features': <Object?, Object?>{
          'fold': <Object?, Object?>{
            'status': 'supported',
            'source': 'android.pm.FEATURE_SENSOR_HINGE_ANGLE',
          },
          'hingeAngle': <Object?, Object?>{'status': 'unsupported'},
        },
      });

      expect(caps.hasFold, isTrue);
      expect(caps.sourceOf(FoldFeature.fold),
          'android.pm.FEATURE_SENSOR_HINGE_ANGLE');
      expect(
          caps.statusOf(FoldFeature.hingeAngle), CapabilityStatus.unsupported);
      expect(caps.formFactor, FoldFormFactor.book);
      expect(caps.rearDisplayModes, <RearDisplayMode>{
        RearDisplayMode.presentation,
        RearDisplayMode.transfer
      });
      // A feature the payload did not mention is unknown, not false.
      expect(caps.statusOf(FoldFeature.coverDisplay), CapabilityStatus.unknown);
    });

    test('an unrecognised feature or status degrades instead of throwing', () {
      final caps = BifoldCapabilities.fromMap(<Object?, Object?>{
        'isResolved': true,
        'features': <Object?, Object?>{
          'teleportation': <Object?, Object?>{'status': 'supported'},
          'fold': <Object?, Object?>{'status': 'quantum'},
        },
      });
      expect(caps.statusOf(FoldFeature.fold), CapabilityStatus.unknown);
      expect(caps.raw, isNotEmpty);
    });
  });

  group('CapabilityResolver', () {
    CapabilityResolver resolver() => CapabilityResolver();

    BifoldCapabilities report(
      Map<FoldFeature, CapabilityStatus> statuses, {
      bool isResolved = true,
      FoldFormFactor formFactor = FoldFormFactor.unknown,
      Set<RearDisplayMode> modes = const <RearDisplayMode>{},
    }) =>
        BifoldCapabilities(
          evidence: <FoldFeature, CapabilityEvidence>{
            for (final entry in statuses.entries)
              entry.key:
                  CapabilityEvidence(status: entry.value, source: 'test'),
          },
          formFactor: formFactor,
          rearDisplayModes: modes,
          isResolved: isResolved,
        );

    test('unknown to supported on any positive evidence', () {
      final r = resolver();
      expect(r.current.hasFold, isFalse);
      r.absorb(report({FoldFeature.fold: CapabilityStatus.supported}));
      expect(r.current.hasFold, isTrue);
    });

    test('supported is sticky: folding a device shut cannot take it away', () {
      // The case this whole design exists for. A closed Android foldable
      // reports no folding feature at all.
      final r = resolver();
      r.absorb(report({FoldFeature.fold: CapabilityStatus.supported}));
      r.absorb(report({FoldFeature.fold: CapabilityStatus.unknown}));
      expect(r.current.hasFold, isTrue,
          reason: 'an absence of observation is not evidence of absence');

      // Even an explicit negative must not demote it.
      r.absorb(report({FoldFeature.fold: CapabilityStatus.unsupported}));
      expect(r.current.hasFold, isTrue);
    });

    test('unknown stays unknown when nothing is reported', () {
      final r = resolver();
      r.absorb(
          report({FoldFeature.halfOpenedPosture: CapabilityStatus.unknown}));
      expect(r.current.statusOf(FoldFeature.halfOpenedPosture),
          CapabilityStatus.unknown);
      expect(r.current.hasHalfOpenedPosture, isFalse);
    });

    test('an authoritative negative does establish unsupported', () {
      final r = resolver();
      r.absorb(report({FoldFeature.hingeAngle: CapabilityStatus.unsupported}));
      expect(r.current.statusOf(FoldFeature.hingeAngle),
          CapabilityStatus.unsupported);
    });

    test('unsupported may be overturned by positive evidence', () {
      final r = resolver();
      r.absorb(report({FoldFeature.rearDisplay: CapabilityStatus.unsupported}));
      r.absorb(report({FoldFeature.rearDisplay: CapabilityStatus.supported}));
      expect(r.current.hasRearDisplay, isTrue);
    });

    test('a known form factor is never replaced by an unknown one', () {
      final r = resolver();
      r.absorb(report(const {}, formFactor: FoldFormFactor.book));
      r.absorb(report(const {}));
      expect(r.current.formFactor, FoldFormFactor.book);
    });

    test('rear display modes accumulate', () {
      final r = resolver();
      r.absorb(report(const {}, modes: const {RearDisplayMode.presentation}));
      r.absorb(report(const {}, modes: const {RearDisplayMode.transfer}));
      expect(r.current.rearDisplayModes, hasLength(2));
    });

    test('isResolved latches once anything resolves', () {
      final r = resolver();
      expect(r.current.isResolved, isFalse);
      r.absorb(report(const {}));
      expect(r.current.isResolved, isTrue);
      r.absorb(BifoldCapabilities.unresolved);
      expect(r.current.isResolved, isTrue);
    });

    test('reset forgets everything', () {
      final r = resolver();
      r.absorb(report({FoldFeature.fold: CapabilityStatus.supported}));
      r.reset();
      expect(r.current, BifoldCapabilities.unresolved);
    });
  });

  group('BifoldCapabilityFakes', () {
    test('book and flip differ in shape, not in fold', () {
      expect(BifoldCapabilityFakes.book().formFactor, FoldFormFactor.book);
      expect(BifoldCapabilityFakes.flip().formFactor, FoldFormFactor.flip);
      expect(BifoldCapabilityFakes.book().hasFold, isTrue);
      expect(BifoldCapabilityFakes.flip().hasFold, isTrue);
    });

    test('book with a rear display reports the presentation mode', () {
      expect(BifoldCapabilityFakes.book().hasRearDisplay, isFalse);
      final withRear = BifoldCapabilityFakes.book(rearDisplay: true);
      expect(withRear.hasRearDisplay, isTrue);
      expect(withRear.rearDisplayModes, contains(RearDisplayMode.presentation));
    });

    test('an unopened foldable knows it folds but not how', () {
      final caps = BifoldCapabilityFakes.unopenedFoldable();
      expect(caps.hasFold, isTrue);
      expect(caps.statusOf(FoldFeature.halfOpenedPosture),
          CapabilityStatus.unknown);
      expect(caps.formFactor, FoldFormFactor.unknown);
    });

    test('implied capabilities never claim more than the state shows', () {
      final open = BifoldCapabilityFakes.impliedBy(
        FoldInfoFakes.partiallyOpen(viewSize: const Size(800, 1000)),
      );
      expect(open.hasFold, isTrue);
      expect(open.hasHalfOpenedPosture, isTrue);
      expect(open.hasReservedRegions, isTrue);
      // Never observed, so never claimed.
      expect(open.statusOf(FoldFeature.rearDisplay), CapabilityStatus.unknown);

      // An unresolved no-fold state must not be read as "cannot fold".
      expect(BifoldCapabilityFakes.impliedBy(FoldInfo.unsupported),
          BifoldCapabilities.unresolved);
      expect(BifoldCapabilityFakes.impliedBy(FoldInfo.none),
          BifoldCapabilities.none);
    });
  });

  group('FoldInfo.isResolved', () {
    test('unsupported is unresolved; none is resolved', () {
      expect(FoldInfo.unsupported.isResolved, isFalse);
      expect(FoldInfo.none.isResolved, isTrue);
      expect(FoldInfo.unsupported, isNot(FoldInfo.none));
    });

    test('a decoded payload is resolved even without the key', () {
      final info = FoldInfo.fromMap(<Object?, Object?>{
        'version': 1,
        'isFoldable': false,
      });
      expect(info.isResolved, isTrue,
          reason: 'the platform answered, which is what resolved means');
    });
  });
}
