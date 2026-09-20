import 'package:bifold/bifold.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FoldDisplay.fromName', () {
    test('decodes the known spellings', () {
      expect(FoldDisplay.fromName('outer'), FoldDisplay.outer);
      expect(FoldDisplay.fromName('inner'), FoldDisplay.inner);
      expect(FoldDisplay.fromName('none'), FoldDisplay.none);
    });

    test('degrades unknown and missing values to none', () {
      expect(FoldDisplay.fromName('tertiary'), FoldDisplay.none);
      expect(FoldDisplay.fromName(null), FoldDisplay.none);
      expect(FoldDisplay.fromName(''), FoldDisplay.none);
    });
  });

  group('FoldPose.fromName', () {
    test('decodes the known spellings', () {
      expect(FoldPose.fromName('closed'), FoldPose.closed);
      expect(FoldPose.fromName('partiallyOpen'), FoldPose.partiallyOpen);
      expect(FoldPose.fromName('fullyOpen'), FoldPose.fullyOpen);
    });

    test('degrades unknown values to unknown', () {
      // A newer OS reporting a pose this build has never heard of must not
      // crash it.
      expect(FoldPose.fromName('tabletop'), FoldPose.unknown);
      expect(FoldPose.fromName(null), FoldPose.unknown);
    });
  });

  group('RegionKind.fromName', () {
    test('decodes the known spellings', () {
      expect(RegionKind.fromName('division'), RegionKind.division);
      expect(RegionKind.fromName('occlusion'), RegionKind.occlusion);
    });

    test('degrades unknown kinds to unknown rather than dropping them', () {
      // An unrecognised region is still an area to avoid, so it survives
      // decoding instead of vanishing.
      expect(RegionKind.fromName('sensor'), RegionKind.unknown);
    });
  });

  group('FoldRegion.fromMap', () {
    test('decodes a complete region', () {
      final region = FoldRegion.fromMap(const <Object?, Object?>{
        'kind': 'division',
        'left': 0.0,
        'top': 490.0,
        'right': 800.0,
        'bottom': 510.0,
        'marginLeft': 0.0,
        'marginTop': 12.0,
        'marginRight': 0.0,
        'marginBottom': 12.0,
        'isActive': true,
      });

      expect(region.kind, RegionKind.division);
      expect(region.frame, const Rect.fromLTRB(0, 490, 800, 510));
      expect(region.margins, const EdgeInsets.symmetric(vertical: 12));
      expect(region.isActive, isTrue);
    });

    test('accepts ints where doubles are expected', () {
      // The standard message codec sends whole numbers as ints.
      final region = FoldRegion.fromMap(const <Object?, Object?>{
        'kind': 'occlusion',
        'left': 380,
        'top': 0,
        'right': 420,
        'bottom': 40,
        'isActive': false,
      });

      expect(region.frame, const Rect.fromLTRB(380, 0, 420, 40));
      expect(region.margins, EdgeInsets.zero);
    });

    test('falls back to zero for missing or malformed numbers', () {
      final region = FoldRegion.fromMap(const <Object?, Object?>{
        'kind': 'division',
        'left': 'not a number',
        'isActive': true,
      });

      expect(region.frame, Rect.zero);
      expect(region.margins, EdgeInsets.zero);
    });

    test('treats a missing isActive as inactive', () {
      final region = FoldRegion.fromMap(const <Object?, Object?>{
        'kind': 'occlusion',
      });
      expect(region.isActive, isFalse);
    });

    test('avoidanceArea inflates the frame by the margins', () {
      const region = FoldRegion(
        kind: RegionKind.division,
        frame: Rect.fromLTRB(0, 100, 400, 120),
        margins: EdgeInsets.symmetric(vertical: 10),
        isActive: true,
      );
      expect(region.avoidanceArea, const Rect.fromLTRB(0, 90, 400, 130));
    });

    test('value equality', () {
      const a = FoldRegion(
        kind: RegionKind.division,
        frame: Rect.fromLTRB(0, 1, 2, 3),
        margins: EdgeInsets.zero,
        isActive: true,
      );
      const b = FoldRegion(
        kind: RegionKind.division,
        frame: Rect.fromLTRB(0, 1, 2, 3),
        margins: EdgeInsets.zero,
        isActive: true,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('FoldRegion.isSeparating', () {
    const size = Size(800, 1000);

    test('is true for a full-width band with thickness', () {
      const region = FoldRegion(
        kind: RegionKind.division,
        frame: Rect.fromLTRB(0, 490, 800, 510),
        margins: EdgeInsets.zero,
        isActive: true,
      );
      expect(region.isSeparating(size), isTrue);
      expect(region.isHorizontal, isTrue);
    });

    test('is false for a zero-thickness crease', () {
      // The display creases without a gap, so content can cross it.
      const region = FoldRegion(
        kind: RegionKind.division,
        frame: Rect.fromLTRB(0, 500, 800, 500),
        margins: EdgeInsets.zero,
        isActive: true,
      );
      expect(region.isSeparating(size), isFalse);
    });

    test('is false for a cutout that does not span the view', () {
      const region = FoldRegion(
        kind: RegionKind.occlusion,
        frame: Rect.fromLTWH(380, 0, 40, 40),
        margins: EdgeInsets.zero,
        isActive: true,
      );
      expect(region.isSeparating(size), isFalse);
    });

    test('is true for a full-height band, reported as vertical', () {
      const region = FoldRegion(
        kind: RegionKind.division,
        frame: Rect.fromLTRB(390, 0, 410, 1000),
        margins: EdgeInsets.zero,
        isActive: true,
      );
      expect(region.isSeparating(size), isTrue);
      expect(region.isHorizontal, isFalse);
    });
  });

  group('FoldInfo.fromMap', () {
    test('decodes a full payload', () {
      final info = FoldInfo.fromMap(const <Object?, Object?>{
        'version': 1,
        'isFoldable': true,
        'display': 'inner',
        'pose': 'partiallyOpen',
        'regions': <Object?>[
          <Object?, Object?>{
            'kind': 'division',
            'left': 0.0,
            'top': 490.0,
            'right': 800.0,
            'bottom': 510.0,
            'isActive': true,
          },
        ],
      });

      expect(info.isFoldable, isTrue);
      expect(info.display, FoldDisplay.inner);
      expect(info.pose, FoldPose.partiallyOpen);
      expect(info.regions, hasLength(1));
      expect(info.division, isNotNull);
    });

    test('decodes an empty payload to the unsupported state', () {
      expect(
        FoldInfo.fromMap(const <Object?, Object?>{}),
        FoldInfo.unsupported,
      );
    });

    test('survives a payload from a newer native build', () {
      // Unknown enum spellings and extra keys must not throw.
      final info = FoldInfo.fromMap(const <Object?, Object?>{
        'version': 99,
        'isFoldable': true,
        'display': 'auxiliary',
        'pose': 'inverted',
        'hingeAngle': 42.0,
        'regions': <Object?>[
          <Object?, Object?>{'kind': 'sensor', 'isActive': true},
        ],
      });

      expect(info.isFoldable, isTrue);
      expect(info.display, FoldDisplay.none);
      expect(info.pose, FoldPose.unknown);
      expect(info.regions.single.kind, RegionKind.unknown);
    });

    test('drops malformed region entries without dropping the rest', () {
      final info = FoldInfo.fromMap(const <Object?, Object?>{
        'isFoldable': true,
        'regions': <Object?>[
          'not a map',
          <Object?, Object?>{'kind': 'division', 'isActive': true},
          42,
        ],
      });
      expect(info.regions, hasLength(1));
    });

    test('tolerates regions being the wrong type entirely', () {
      final info = FoldInfo.fromMap(const <Object?, Object?>{
        'isFoldable': true,
        'regions': 'unexpected',
      });
      expect(info.regions, isEmpty);
    });

    test('exposes an unmodifiable region list', () {
      final info = FoldInfo.fromMap(const <Object?, Object?>{
        'regions': <Object?>[
          <Object?, Object?>{'kind': 'division'},
        ],
      });
      expect(
        () => info.regions.add(
          const FoldRegion(
            kind: RegionKind.division,
            frame: Rect.zero,
            margins: EdgeInsets.zero,
            isActive: true,
          ),
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('FoldInfo.division', () {
    test('returns the active division', () {
      final info = FoldInfoFakes.partiallyOpen(
        viewSize: const Size(800, 1000),
      );
      expect(info.division, isNotNull);
      expect(info.division!.kind, RegionKind.division);
    });

    test('is null when the division is present but inactive', () {
      // The trap this exists to catch: a flat display still reports a
      // division, so a layout keyed on presence rather than activity splits
      // when it should not.
      final info = FoldInfoFakes.fullyOpen(viewSize: const Size(800, 1000));
      expect(
        info.regions.any((r) => r.kind == RegionKind.division),
        isTrue,
      );
      expect(info.division, isNull);
    });

    test('is null when closed', () {
      expect(FoldInfoFakes.closed.division, isNull);
      expect(FoldInfoFakes.closed.regions, isEmpty);
    });

    test('is null on an unsupported device', () {
      expect(FoldInfo.unsupported.division, isNull);
    });
  });

  group('FoldInfo', () {
    test('unsupported is the documented no-fold state', () {
      expect(FoldInfo.unsupported.isFoldable, isFalse);
      expect(FoldInfo.unsupported.display, FoldDisplay.none);
      expect(FoldInfo.unsupported.pose, FoldPose.unknown);
      expect(FoldInfo.unsupported.regions, isEmpty);
    });

    test('activeRegions filters by isActive', () {
      final info = FoldInfoFakes.partiallyOpen(
        viewSize: const Size(800, 1000),
        cameraActive: false,
      );
      expect(info.regions.length, 2);
      expect(info.activeRegions, hasLength(1));
    });

    test('copyWith replaces only the named fields', () {
      const base = FoldInfo.unsupported;
      final copy = base.copyWith(isFoldable: true, pose: FoldPose.fullyOpen);
      expect(copy.isFoldable, isTrue);
      expect(copy.pose, FoldPose.fullyOpen);
      expect(copy.display, base.display);
      expect(copy.regions, base.regions);
    });

    test('value equality compares regions by value', () {
      final a = FoldInfoFakes.partiallyOpen(viewSize: const Size(800, 1000));
      final b = FoldInfoFakes.partiallyOpen(viewSize: const Size(800, 1000));
      expect(a, b);
      expect(a.hashCode, b.hashCode);

      final c = FoldInfoFakes.partiallyOpen(
        viewSize: const Size(800, 1000),
        thickness: 40,
      );
      expect(a, isNot(c));
    });
  });

  group('payload version', () {
    test('matches the version the native side is documented to send', () {
      // Bump this together with `payloadVersion` in BifoldPlugin.swift.
      expect(kBifoldPayloadVersion, 1);
    });
  });
}
