import 'package:bifold/bifold.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('dev.bifold/methods');

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('without a native implementation', () {
    test('measure returns null rather than throwing', () async {
      expect(
        await BifoldArrangement.measure(size: const Size(800, 1000)),
        isNull,
      );
    });

    test('release is a no-op', () async {
      await BifoldArrangement.release();
    });
  });

  group('decoding', () {
    test('decodes a real split', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'measureArrangement');
        expect(call.arguments, <String, Object?>{
          'width': 800.0,
          'height': 1000.0,
          'axis': 'vertical',
        });
        return <Object?, Object?>{
          'axis': 'vertical',
          'primary': <Object?, Object?>{
            'left': 0.0,
            'top': 0.0,
            'right': 800.0,
            'bottom': 500.0,
            'visible': true,
          },
          'secondary': <Object?, Object?>{
            'left': 0.0,
            'top': 500.0,
            'right': 800.0,
            'bottom': 1000.0,
            'visible': true,
          },
        };
      });

      final measured = await BifoldArrangement.measure(
        size: const Size(800, 1000),
        axis: ArrangementAxis.vertical,
      );

      expect(measured, isNotNull);
      expect(measured!.axis, ArrangementAxis.vertical);
      expect(measured.isSplit, isTrue);
      expect(measured.primary.bounds, const Rect.fromLTRB(0, 0, 800, 500));
      expect(measured.secondary.bounds, const Rect.fromLTRB(0, 500, 800, 1000));
    });

    test('reports a collapsed arrangement as not split', () async {
      // What the platform does when the device is shut: one full-size pane,
      // the other not shown at all.
      messenger.setMockMethodCallHandler(channel, (call) async {
        return <Object?, Object?>{
          'axis': 'horizontal',
          'primary': <Object?, Object?>{
            'left': 0.0,
            'top': 0.0,
            'right': 871.0,
            'bottom': 669.0,
            'visible': true,
          },
          'secondary': <Object?, Object?>{
            'left': 0.0,
            'top': 0.0,
            'right': 0.0,
            'bottom': 0.0,
            'visible': false,
          },
        };
      });

      final measured = await BifoldArrangement.measure(
        size: const Size(871, 669),
      );

      expect(measured!.isSplit, isFalse);
      expect(measured.primary.isVisible, isTrue);
      expect(measured.secondary.isVisible, isFalse);
    });

    test('survives a malformed payload', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => <Object?, Object?>{'primary': 'nonsense'},
      );

      final measured = await BifoldArrangement.measure(
        size: const Size(800, 1000),
      );
      expect(measured!.primary.bounds, Rect.zero);
      expect(measured.primary.isVisible, isFalse);
      expect(measured.isSplit, isFalse);
    });

    test('a null reply means no arrangement', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      expect(
        await BifoldArrangement.measure(size: const Size(800, 1000)),
        isNull,
      );
    });

    test('value equality', () {
      const a = ArrangementPane(
        bounds: Rect.fromLTRB(0, 0, 10, 10),
        isVisible: true,
      );
      const b = ArrangementPane(
        bounds: Rect.fromLTRB(0, 0, 10, 10),
        isVisible: true,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
