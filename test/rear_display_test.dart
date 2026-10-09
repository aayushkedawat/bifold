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

    test('unresolved and none report the same statuses, differently', () {
      // The distinction the four states could not express on their own:
      // "this device cannot present" and "nothing has reported yet" both read
      // as unsupported, and only isResolved tells them apart. Without it, a
      // UI had to hide its control before the platform had spoken.
      expect(
        RearDisplayAvailability.unresolved.presentation,
        RearDisplayStatus.unsupported,
      );
      expect(RearDisplayAvailability.unresolved.isResolved, isFalse);
      expect(RearDisplayAvailability.none.isResolved, isTrue);
      expect(RearDisplayAvailability.unresolved,
          isNot(RearDisplayAvailability.none));
      expect(
        RearDisplayAvailability.unresolved.toString(),
        contains('unresolved'),
      );
    });

    test('isResolved is read strictly from the payload', () {
      expect(
        RearDisplayAvailability.fromMap(const <Object?, Object?>{
          'presentation': 'available',
          'transfer': 'unsupported',
        }).isResolved,
        isFalse,
        reason: 'no key means the platform claimed no answer',
      );
      expect(
        RearDisplayAvailability.fromMap(const <Object?, Object?>{
          'presentation': 'available',
          'transfer': 'unsupported',
          'isResolved': true,
        }).isResolved,
        isTrue,
      );
    });

    test('equality and hashCode cover every field', () {
      // The only assertion on == used to be against an identical instance,
      // which short-circuits before comparing anything.
      const a = RearDisplayAvailability(
        presentation: RearDisplayStatus.available,
        transfer: RearDisplayStatus.unsupported,
        isResolved: true,
      );
      const same = RearDisplayAvailability(
        presentation: RearDisplayStatus.available,
        transfer: RearDisplayStatus.unsupported,
        isResolved: true,
      );
      const differentMode = RearDisplayAvailability(
        presentation: RearDisplayStatus.active,
        transfer: RearDisplayStatus.unsupported,
        isResolved: true,
      );
      const differentResolution = RearDisplayAvailability(
        presentation: RearDisplayStatus.available,
        transfer: RearDisplayStatus.unsupported,
      );

      expect(a, same);
      expect(a.hashCode, same.hashCode);
      expect(a, isNot(differentMode));
      expect(a, isNot(differentResolution));
      expect(a.toString(), contains('available'));
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

  _adopterFacingTests();
}

/// What a downstream team can now do without touching a platform channel.
///
/// This is the point of routing rear display through `BifoldPlatform`: before
/// it, testing these five situations meant hand-writing `StandardMethodCodec`
/// plumbing against an unexported channel name, and only one case could be
/// covered per test file because the availability stream was a process-global
/// memoised singleton.
void _adopterFacingTests() {
  group('FakeBifoldPlatform rear display', () {
    late FakeBifoldPlatform platform;

    setUp(() {
      platform = FakeBifoldPlatform(rearDisplay: RearDisplayFakes.available);
      BifoldPlatform.instance = platform;
    });

    tearDown(() async => platform.dispose());

    test('every documented state can be driven, in one file', () async {
      final seen = <RearDisplayAvailability>[];
      final sub = BifoldRearDisplay.availability.listen(seen.add);
      addTearDown(sub.cancel);

      for (final state in <RearDisplayAvailability>[
        RearDisplayFakes.unresolved,
        RearDisplayFakes.unsupported,
        RearDisplayFakes.unavailable,
        RearDisplayFakes.available,
        RearDisplayFakes.presenting,
        RearDisplayFakes.bothAvailable,
      ]) {
        platform.emitRearDisplay(state);
      }
      await pumpEventQueue();

      expect(seen, hasLength(6));
      expect(seen.first.isResolved, isFalse);
      expect(seen[1], RearDisplayAvailability.none);
      expect(seen[4].isActive, isTrue);
      expect(seen.last.transfer, RearDisplayStatus.available);
    });

    test('presenting moves the status to active and back', () async {
      expect(await BifoldRearDisplay.present(entrypoint: 'rearDisplayMain'),
          isTrue);
      expect(
        (await BifoldRearDisplay.current).presentation,
        RearDisplayStatus.active,
      );

      await BifoldRearDisplay.end();
      expect(
        (await BifoldRearDisplay.current).presentation,
        RearDisplayStatus.available,
      );

      expect(platform.rearDisplayCalls,
          <String>['present:rearDisplayMain', 'end']);
    });

    test('the system refusing is not an error', () async {
      platform.rearDisplayRequestsSucceed = false;
      expect(
        await BifoldRearDisplay.present(entrypoint: 'rearDisplayMain'),
        isFalse,
      );
      expect(await BifoldRearDisplay.transferActivity(), isFalse);
      // Nothing threw, and the status never claimed a session.
      expect((await BifoldRearDisplay.current).isActive, isFalse);
    });

    test('transfer is drivable, which only Android offers', () async {
      expect(await BifoldRearDisplay.transferActivity(), isTrue);
      expect(
          (await BifoldRearDisplay.current).transfer, RearDisplayStatus.active);
    });
  });

  group('FakeBifoldPlatform test affordances', () {
    test('reports stream requests and whether anything is subscribed',
        () async {
      final platform = FakeBifoldPlatform();
      addTearDown(platform.dispose);
      expect(platform.foldStreamRequests, 0);
      expect(platform.foldStreamIsSubscribed, isFalse);

      final a = platform.foldInfoStream().listen((_) {});
      final b = platform.foldInfoStream().listen((_) {});
      await pumpEventQueue();
      // Two callers took the stream; one subscription sits behind them.
      expect(platform.foldStreamRequests, 2);
      expect(platform.foldStreamIsSubscribed, isTrue);

      await a.cancel();
      expect(platform.foldStreamIsSubscribed, isTrue,
          reason: 'one listener remains');
      await b.cancel();
      await pumpEventQueue();
      expect(platform.foldStreamIsSubscribed, isFalse);
    });

    test('can hold a one-shot read open', () async {
      final platform = FakeBifoldPlatform(initial: FoldInfoFakes.closed);
      addTearDown(platform.dispose);
      platform.holdNextRead();

      var settled = false;
      final pending = platform.getFoldInfo().then((info) {
        settled = true;
        return info;
      });
      await pumpEventQueue();
      expect(settled, isFalse, reason: 'the read is deliberately hanging');

      platform.completePendingRead(FoldInfoFakes.flat);
      expect(await pending, FoldInfoFakes.flat);
    });

    test('can push an error through the fold stream', () async {
      final platform = FakeBifoldPlatform();
      addTearDown(platform.dispose);

      final errors = <Object>[];
      final sub = platform.foldInfoStream().listen(
            (_) {},
            onError: errors.add,
          );
      addTearDown(sub.cancel);

      platform.emitError(StateError('the platform fell over'));
      await pumpEventQueue();
      expect(errors, hasLength(1));
    });
  });
}
