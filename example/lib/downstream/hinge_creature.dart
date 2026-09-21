import 'package:bifold/bifold.dart';
import 'package:flutter/material.dart';

/// **Downstream example A: a creature that reacts to the hinge.**
///
/// The API test this exists for: it must run on a foldable iPhone, an Android
/// foldable and a phone that does not fold, with **no platform checks**.
/// There is no `Platform.isIOS` here and there is nothing to add.
///
/// Note that it branches on *capability* to decide what kind of creature to
/// be, and on *state* to decide what it is doing — two different questions.
class HingeCreature extends StatelessWidget {
  /// Creates the creature.
  const HingeCreature({super.key});

  @override
  Widget build(BuildContext context) {
    final BifoldCapabilities can = Bifold.capabilitiesOf(context);
    final FoldInfo now = Bifold.of(context);

    // Not "hasFold == false", which would also be true before the platform
    // has answered and would make the creature flicker at launch.
    if (can.statusOf(FoldFeature.fold) == CapabilityStatus.unsupported) {
      return const _Creature(mood: 'asleep', tilt: 0);
    }
    if (!can.isResolved) {
      return const _Creature(mood: 'waking', tilt: 0);
    }

    // A hinge angle is a bonus, not a requirement: the sensor may be absent,
    // or present and silent. Pose always answers.
    final double? degrees = now.hingeAngleDegrees;
    if (can.hasHingeAngle && degrees != null) {
      return _Creature(mood: 'watching', tilt: (180 - degrees) / 180);
    }

    return switch (now.pose) {
      FoldPose.closed => const _Creature(mood: 'curled up', tilt: 1),
      FoldPose.partiallyOpen => const _Creature(mood: 'peeking', tilt: 0.5),
      FoldPose.fullyOpen => const _Creature(mood: 'stretching', tilt: 0),
      FoldPose.unknown => const _Creature(mood: 'still', tilt: 0),
    };
  }
}

class _Creature extends StatelessWidget {
  const _Creature({required this.mood, required this.tilt});

  final String mood;
  final double tilt;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Transform.rotate(angle: tilt, child: const Text('(o_o)')),
        Text(mood),
      ],
    ),
  );
}
