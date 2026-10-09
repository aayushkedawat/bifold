import 'dart:io';

import 'package:bifold/bifold.dart';
import 'package:bifold/src/method_channel_bifold.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late MethodChannelBifold platform;

  setUp(() {
    platform = MethodChannelBifold();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(platform.methodChannel, null);
  });

  group('getFoldInfo', () {
    test('decodes a payload from the native side', () async {
      messenger.setMockMethodCallHandler(platform.methodChannel, (call) async {
        expect(call.method, 'getFoldInfo');
        return <Object?, Object?>{
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
              'marginTop': 12.0,
              'marginBottom': 12.0,
              'isActive': true,
            },
          ],
        };
      });

      final info = await platform.getFoldInfo();
      expect(info.isFoldable, isTrue);
      expect(info.display, FoldDisplay.inner);
      expect(info.pose, FoldPose.partiallyOpen);
      expect(info.division?.frame.top, 490.0);
    });

    test('reports a settled no-fold when there is no native implementation',
        () async {
      // This is what web, desktop and any unregistered plugin does: the
      // channel has no handler, so the call raises MissingPluginException.
      // That is an answer rather than silence -- having no implementation
      // conclusively means no fold -- so it is FoldInfo.none, which resolves.
      // While this returned FoldInfo.unsupported, FoldInfo.none was
      // unreachable from the real platform path and a consumer gating its
      // first layout on isResolved waited forever.
      final info = await platform.getFoldInfo();
      expect(info, FoldInfo.none);
      expect(info.isResolved, isTrue);
    });

    test('reports a settled no-fold when the native side returns null',
        () async {
      messenger.setMockMethodCallHandler(
        platform.methodChannel,
        (call) async => null,
      );
      expect(await platform.getFoldInfo(), FoldInfo.none);
    });

    test('reports unsupported when the native side raises', () async {
      messenger.setMockMethodCallHandler(
        platform.methodChannel,
        (call) async => throw PlatformException(
          code: 'no_view',
          message: 'The Flutter view is not available yet.',
        ),
      );

      // The failure is reported to FlutterError rather than thrown, so callers
      // never have to guard a fold query with a try/catch.
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);

      expect(await platform.getFoldInfo(), FoldInfo.unsupported);
      expect(errors, hasLength(1));
      expect(errors.single.library, 'bifold');
    });
  });

  group('foldInfoStream', () {
    /// Stands in for a registered native side, so the stream's probe finds
    /// one. Without it the probe reports no plugin, which is what every
    /// platform with no native implementation does.
    void installNativeSide() {
      messenger.setMockMethodCallHandler(
        platform.methodChannel,
        (call) async => <Object?, Object?>{'version': 1, 'isFoldable': false},
      );
    }

    test('decodes events from the event channel', () async {
      installNativeSide();
      final emitted = <FoldInfo>[];
      final subscription = platform.foldInfoStream().listen(emitted.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      await _emit(messenger, <Object?, Object?>{
        'version': 1,
        'isFoldable': true,
        'display': 'inner',
        'pose': 'fullyOpen',
        'regions': <Object?>[],
      });
      await _emit(messenger, <Object?, Object?>{
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

      expect(emitted, hasLength(2));
      expect(emitted.first.pose, FoldPose.fullyOpen);
      expect(emitted.first.division, isNull);
      // Regions arriving after the first event is the normal case, not an
      // edge case: they are not available until after the first layout pass.
      expect(emitted.last.division, isNotNull);
    });

    test('decodes a non-map event to the unsupported state', () async {
      installNativeSide();
      final emitted = <FoldInfo>[];
      final subscription = platform.foldInfoStream().listen(emitted.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      await _emit(messenger, 'unexpected');
      expect(emitted.single, FoldInfo.unsupported);
    });

    test('never touches the event channel when there is no native side',
        () async {
      // Regression test. Listening to an event channel with no handler makes
      // EventChannel report a MissingPluginException through
      // FlutterError.reportError, which no amount of error handling on this
      // side can suppress. It reached the console on every Android launch.
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);

      final emitted = <FoldInfo>[];
      final subscription = platform.foldInfoStream().listen(emitted.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      expect(errors, isEmpty, reason: 'no plugin is a state, not a failure');
      // Settled, not silent: there is no native side, so there is no fold.
      expect(emitted.single, FoldInfo.none);
      expect(emitted.single.isResolved, isTrue);
    });

    test('subscribes when the native side answers with a failure', () async {
      // A PlatformException means the plugin is there and unhappy, which is a
      // different thing from the plugin not being there at all.
      messenger.setMockMethodCallHandler(
        platform.methodChannel,
        (call) async => throw PlatformException(code: 'no_view'),
      );

      final emitted = <FoldInfo>[];
      final subscription = platform.foldInfoStream().listen(emitted.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      await _emit(messenger, <Object?, Object?>{
        'version': 1,
        'isFoldable': true,
        'display': 'inner',
        'pose': 'fullyOpen',
        'regions': <Object?>[],
      });
      expect(emitted.single.isFoldable, isTrue);
    });

    test('probes again when a new listener arrives after the last one left',
        () async {
      // The stream is cached, so the second BifoldScope in an app's lifetime
      // re-enters through onListen rather than building a fresh stream. It
      // has to re-probe and re-subscribe, or it would stay silent forever.
      var probes = 0;
      messenger.setMockMethodCallHandler(platform.methodChannel, (call) async {
        probes++;
        return <Object?, Object?>{'version': 1, 'isFoldable': false};
      });

      final first = <FoldInfo>[];
      final firstSub = platform.foldInfoStream().listen(first.add);
      await pumpEventQueue();
      await _emit(messenger, <Object?, Object?>{
        'version': 1,
        'isFoldable': true,
      });
      expect(first, hasLength(1));
      expect(probes, 1);

      await firstSub.cancel();
      await pumpEventQueue();

      final second = <FoldInfo>[];
      final secondSub = platform.foldInfoStream().listen(second.add);
      addTearDown(secondSub.cancel);
      await pumpEventQueue();
      await _emit(messenger, <Object?, Object?>{
        'version': 1,
        'isFoldable': true,
      });

      expect(second, hasLength(1),
          reason: 'the stream went silent on relisten');
      expect(probes, 2);
    });

    test('returns the same broadcast stream to every caller', () {
      // Several BifoldScopes must not each open a native subscription.
      expect(
        identical(platform.foldInfoStream(), platform.foldInfoStream()),
        isTrue,
      );
      expect(platform.foldInfoStream().isBroadcast, isTrue);
    });
  });

  group('channel names', () {
    test('are the names this class actually uses', () {
      expect(platform.methodChannel.name, kBifoldMethodChannelName);
      expect(platform.eventChannel.name, kBifoldEventChannelName);
    });

    test('appear verbatim in both native implementations', () {
      // The previous version of this test asserted that each constant equalled
      // its own literal, which no change could ever break -- while its comment
      // claimed to guard against a native rename. Channel names and method
      // names are string literals duplicated across Dart, Swift and Kotlin
      // with no shared schema, so the only test that can catch a rename is one
      // that reads the other two languages.
      final swift = File('ios/bifold/Sources/bifold/BifoldPlugin.swift')
          .readAsStringSync();
      final kotlin =
          File('android/src/main/kotlin/dev/bifold/bifold/BifoldPlugin.kt')
              .readAsStringSync();

      for (final name in <String>[
        kBifoldMethodChannelName,
        kBifoldEventChannelName,
      ]) {
        expect(swift, contains(name), reason: '$name is missing from iOS');
        expect(kotlin, contains(name), reason: '$name is missing from Android');
      }
    });

    test('every method Dart invokes is handled by both platforms', () {
      final swift = File('ios/bifold/Sources/bifold/BifoldPlugin.swift')
          .readAsStringSync();
      final kotlin =
          File('android/src/main/kotlin/dev/bifold/bifold/BifoldPlugin.kt')
              .readAsStringSync();

      // Dart calls these on every platform, so both sides must answer them --
      // Android answers the iOS-only ones with a refusal rather than letting
      // them fall through to notImplemented.
      for (final method in <String>[
        'getFoldInfo',
        'getCapabilities',
        'debugDescribeNativeApi',
      ]) {
        expect(swift, contains('"$method"'),
            reason: '$method is not handled on iOS');
        expect(kotlin, contains('"$method"'),
            reason: '$method is not handled on Android');
      }
    });

    test('both platforms stamp the keys Dart reads strictly', () {
      // isResolved is read with `== true`, so a platform that omits it
      // reports "nothing established" forever. capabilityRevision gates the
      // capability re-query. Neither failure is visible in Dart alone.
      final iosFold =
          File('ios/bifold/Sources/bifold/FoldReader.swift').readAsStringSync();
      final androidFold =
          File('android/src/main/kotlin/dev/bifold/bifold/FoldReader.kt')
              .readAsStringSync();

      for (final key in <String>['isResolved', 'capabilityRevision']) {
        expect(iosFold, contains('"$key"'),
            reason: 'the iOS fold payload omits $key');
        expect(androidFold, contains('"$key"'),
            reason: 'the Android fold payload omits $key');
      }
    });
  });

  group('getCapabilities', () {
    test('a null payload settles as no fold support', () async {
      messenger.setMockMethodCallHandler(
          platform.methodChannel, (_) async => null);
      final caps = await platform.getCapabilities();
      expect(caps.isResolved, isTrue);
      expect(caps.hasFold, isFalse);
      expect(caps.statusOf(FoldFeature.fold), CapabilityStatus.unsupported);
    });

    test('a missing plugin settles as no fold support', () async {
      messenger.setMockMethodCallHandler(platform.methodChannel, (call) async {
        throw MissingPluginException('no implementation for ${call.method}');
      });
      final caps = await platform.getCapabilities();
      expect(caps, BifoldCapabilities.none);
    });

    test('a decoded payload is absorbed, and stickiness applies', () async {
      messenger.setMockMethodCallHandler(platform.methodChannel, (_) async {
        return <Object?, Object?>{
          'isResolved': true,
          'platform': 'android',
          'formFactor': 'book',
          'rearDisplayModes': <Object?>['presentation'],
          'features': <Object?, Object?>{
            'fold': <Object?, Object?>{
              'status': 'supported',
              'source': 'android.feature.hinge_angle',
            },
          },
        };
      });
      final first = await platform.getCapabilities();
      expect(first.hasFold, isTrue);
      expect(first.formFactor, FoldFormFactor.book);
      expect(first.sourceOf(FoldFeature.fold), 'android.feature.hinge_angle');
      // Brief decision 4: platform is readable through raw, never typed.
      expect(first.raw['platform'], 'android');

      // A later report that has forgotten the fold -- which is what a closed
      // foldable produces -- must not take the capability away.
      messenger.setMockMethodCallHandler(platform.methodChannel, (_) async {
        return <Object?, Object?>{
          'isResolved': true,
          'formFactor': 'unknown',
          'features': <Object?, Object?>{},
        };
      });
      final second = await platform.getCapabilities();
      expect(second.hasFold, isTrue, reason: 'supported is sticky');
      expect(second.formFactor, FoldFormFactor.book);
    });

    test('a platform exception claims nothing new', () async {
      messenger.setMockMethodCallHandler(platform.methodChannel, (_) async {
        throw PlatformException(code: 'boom');
      });
      final reported = <Object>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) => reported.add(details.exception);
      addTearDown(() => FlutterError.onError = previous);

      final caps = await platform.getCapabilities();
      // Claiming "no fold support" would be stronger than the evidence: the
      // plugin is there and unhappy, which is not an answer about the device.
      expect(caps, BifoldCapabilities.unresolved);
      expect(reported, hasLength(1));
    });
  });

  group('capabilitiesStream', () {
    test('queries once per capability revision, not once per event', () async {
      var queries = 0;
      messenger.setMockMethodCallHandler(platform.methodChannel, (call) async {
        if (call.method == 'getCapabilities') {
          queries++;
          return <Object?, Object?>{
            'isResolved': true,
            'formFactor': 'book',
            'features': <Object?, Object?>{
              'fold': <Object?, Object?>{'status': 'supported'},
            },
          };
        }
        return <Object?, Object?>{'isFoldable': true, 'isResolved': true};
      });

      final seen = <BifoldCapabilities>[];
      final sub = platform.capabilitiesStream().listen(seen.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();

      // A fold in progress: the hinge angle moves, the capabilities do not,
      // so the native side leaves the revision alone.
      for (var i = 0; i < 60; i++) {
        await _emit(messenger, <Object?, Object?>{
          'isFoldable': true,
          'isResolved': true,
          'pose': 'partiallyOpen',
          'hingeAngle': 0.5 + i * 0.01,
          'capabilityRevision': 0,
        });
      }
      await pumpEventQueue();
      expect(queries, 1,
          reason: '60 hinge samples used to cost 60 platform round trips');

      // A real capability change bumps the revision, and must get through.
      await _emit(messenger, <Object?, Object?>{
        'isFoldable': true,
        'isResolved': true,
        'capabilityRevision': 1,
      });
      await pumpEventQueue();
      expect(queries, 2);
    });
  });
}

/// Pushes [event] through the event channel as the native side would.
Future<void> _emit(TestDefaultBinaryMessenger messenger, Object? event) async {
  await messenger.handlePlatformMessage(
    kBifoldEventChannelName,
    const StandardMethodCodec().encodeSuccessEnvelope(event),
    (_) {},
  );
}
