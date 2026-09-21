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

  group('RearDisplayStatus', () {
    test('decodes each spelling, and anything unknown is unsupported', () {
      expect(
          RearDisplayStatus.fromName('available'), RearDisplayStatus.available);
      expect(RearDisplayStatus.fromName('unavailable'),
          RearDisplayStatus.unavailable);
      expect(RearDisplayStatus.fromName('active'), RearDisplayStatus.active);
      // A newer native build must not make an older Dart one claim support.
      expect(RearDisplayStatus.fromName('teleporting'),
          RearDisplayStatus.unsupported);
      expect(RearDisplayStatus.fromName(null), RearDisplayStatus.unsupported);
    });
  });

  group('RearDisplayAvailability', () {
    test('reports each mode separately', () {
      final a = RearDisplayAvailability.fromMap(const <Object?, Object?>{
        'presentation': 'available',
        'transfer': 'unsupported',
      });
      expect(a.statusOf(RearDisplayMode.presentation),
          RearDisplayStatus.available);
      // What iOS reports: presenting works, moving the app does not exist.
      expect(
          a.statusOf(RearDisplayMode.transfer), RearDisplayStatus.unsupported);
      expect(a.isActive, isFalse);
    });

    test('isActive is true when either mode is running', () {
      const presenting = RearDisplayAvailability(
        presentation: RearDisplayStatus.active,
        transfer: RearDisplayStatus.unsupported,
      );
      const transferring = RearDisplayAvailability(
        presentation: RearDisplayStatus.unsupported,
        transfer: RearDisplayStatus.active,
      );
      expect(presenting.isActive, isTrue);
      expect(transferring.isActive, isTrue);
      expect(RearDisplayAvailability.none.isActive, isFalse);
    });

    test('none is what a platform without support reports', () {
      expect(RearDisplayAvailability.none.presentation,
          RearDisplayStatus.unsupported);
      expect(
          RearDisplayAvailability.none.transfer, RearDisplayStatus.unsupported);
    });
  });

  group('BifoldRearDisplay', () {
    test('every call degrades rather than throwing with no plugin', () async {
      // The whole contract on an unsupported platform.
      expect(await BifoldRearDisplay.current, RearDisplayAvailability.none);
      expect(
        await BifoldRearDisplay.present(entrypoint: 'whatever'),
        isFalse,
      );
      expect(await BifoldRearDisplay.transferActivity(), isFalse);
      await BifoldRearDisplay.end();
    });

    test('passes the entrypoint through and reports the system saying no',
        () async {
      MethodCall? seen;
      messenger.setMockMethodCallHandler(channel, (call) async {
        seen = call;
        // The system declining is a normal answer, not a failure.
        return false;
      });

      expect(
        await BifoldRearDisplay.present(
          entrypoint: 'rearDisplayMain',
          libraryUri: 'package:app/rear.dart',
        ),
        isFalse,
      );
      expect(seen?.method, 'presentOnRearDisplay');
      expect(seen?.arguments, <String, Object?>{
        'entrypoint': 'rearDisplayMain',
        'libraryUri': 'package:app/rear.dart',
      });
    });

    test('reads the status of both modes', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'rearDisplayStatus');
        return <Object?, Object?>{
          'presentation': 'active',
          'transfer': 'unavailable',
        };
      });

      final status = await BifoldRearDisplay.current;
      expect(status.presentation, RearDisplayStatus.active);
      expect(status.transfer, RearDisplayStatus.unavailable);
      expect(status.isActive, isTrue);
    });

    test('a native failure is reported, not thrown', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(code: 'no_activity'),
      );
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);

      expect(await BifoldRearDisplay.present(entrypoint: 'x'), isFalse);
      expect(errors.single.library, 'bifold');
    });
  });
}
