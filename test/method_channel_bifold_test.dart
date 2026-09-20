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

    test('reports unsupported when there is no native implementation',
        () async {
      // This is what every non-iOS platform does: the channel has no handler,
      // so the call raises MissingPluginException.
      expect(await platform.getFoldInfo(), FoldInfo.unsupported);
    });

    test('reports unsupported when the native side returns null', () async {
      messenger.setMockMethodCallHandler(
        platform.methodChannel,
        (call) async => null,
      );
      expect(await platform.getFoldInfo(), FoldInfo.unsupported);
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
    test('decodes events from the event channel', () async {
      final emitted = <FoldInfo>[];
      final subscription = platform.foldInfoStream().listen(emitted.add);
      addTearDown(subscription.cancel);

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
      final emitted = <FoldInfo>[];
      final subscription = platform.foldInfoStream().listen(emitted.add);
      addTearDown(subscription.cancel);

      await _emit(messenger, 'unexpected');
      expect(emitted.single, FoldInfo.unsupported);
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
    test('match the names the native plugin registers', () {
      // Changing either of these without changing BifoldPlugin.swift silently
      // breaks the plugin at runtime, where no test would catch it.
      expect(kBifoldMethodChannelName, 'dev.bifold/methods');
      expect(kBifoldEventChannelName, 'dev.bifold/fold_info');
      expect(platform.methodChannel.name, kBifoldMethodChannelName);
      expect(platform.eventChannel.name, kBifoldEventChannelName);
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
