import 'package:bifold/bifold.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('dev.bifold/methods');

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('without a native implementation', () {
    // Every other platform. Nothing here may throw.
    test('isSupported is false', () async {
      expect(await BifoldCaptureAccessory.isSupported, isFalse);
    });

    test('register returns false rather than throwing', () async {
      expect(
        await BifoldCaptureAccessory.register(entrypoint: 'accessoryMain'),
        isFalse,
      );
    });

    test('unregister and setEnabled are no-ops', () async {
      await BifoldCaptureAccessory.unregister();
      await BifoldCaptureAccessory.setEnabled(true);
    });

    test('isAvailable is false', () async {
      expect(await BifoldCaptureAccessory.isAvailable, isFalse);
    });
  });

  group('against a native implementation', () {
    test('register passes the entrypoint and library', () async {
      MethodCall? seen;
      messenger.setMockMethodCallHandler(channel, (call) async {
        seen = call;
        return true;
      });

      final ok = await BifoldCaptureAccessory.register(
        entrypoint: 'accessoryMain',
        libraryUri: 'package:demo/accessory.dart',
      );

      expect(ok, isTrue);
      expect(seen?.method, 'registerCaptureAccessory');
      expect(
        seen?.arguments,
        <String, Object?>{
          'entrypoint': 'accessoryMain',
          'libraryUri': 'package:demo/accessory.dart',
        },
      );
    });

    test('setEnabled forwards the flag', () async {
      MethodCall? seen;
      messenger.setMockMethodCallHandler(channel, (call) async {
        seen = call;
        return null;
      });

      await BifoldCaptureAccessory.setEnabled(true);
      expect(seen?.method, 'setCaptureAccessoryEnabled');
      expect(seen?.arguments, <String, Object?>{'enabled': true});
    });

    test('a platform failure is reported, not thrown', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(code: 'no_view'),
      );

      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);

      expect(
        await BifoldCaptureAccessory.register(entrypoint: 'accessoryMain'),
        isFalse,
      );
      expect(errors.single.library, 'bifold');
    });

    test('a null reply is treated as unsupported', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      expect(await BifoldCaptureAccessory.isSupported, isFalse);
      expect(
        await BifoldCaptureAccessory.register(entrypoint: 'accessoryMain'),
        isFalse,
      );
    });
  });

  group('availability stream', () {
    test('is broadcast and shared', () {
      expect(BifoldCaptureAccessory.availability.isBroadcast, isTrue);
      expect(
        identical(
          BifoldCaptureAccessory.availability,
          BifoldCaptureAccessory.availability,
        ),
        isTrue,
      );
    });
  });
}
