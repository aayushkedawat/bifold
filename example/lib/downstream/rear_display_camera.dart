import 'package:bifold/bifold.dart';
import 'package:flutter/material.dart';

/// **Downstream example C: a camera with content for the person being filmed.**
///
/// The hardest of the three, and the one that pressure-tests the distinction
/// between capability, availability and state:
///
/// * **capability** — could this device ever show the subject something?
/// * **availability** — may it right now? (the system decides, and says no
///   without a capture session running)
/// * **state** — is it showing something at this moment?
///
/// Collapsing any two of those produces a UI that lies. A device that *can* do
/// this still shows nothing until a capture session is live, and a control
/// that appeared and vanished with availability would flicker.
///
/// Note what each one drives, because that is the whole lesson:
///
/// * capability decides whether the control **exists** — stable for the life
///   of the app, so nothing here flickers;
/// * availability decides whether it is **enabled** — it moves with the
///   capture session, so the control dims rather than disappearing;
/// * state decides what the control **says and does** — start, or stop.
class RearDisplayCamera extends StatefulWidget {
  /// Creates the camera screen.
  const RearDisplayCamera({super.key});

  @override
  State<RearDisplayCamera> createState() => _RearDisplayCameraState();
}

class _RearDisplayCameraState extends State<RearDisplayCamera> {
  @override
  Widget build(BuildContext context) {
    final BifoldCapabilities can = Bifold.capabilitiesOf(context);

    return Column(
      children: <Widget>[
        const Expanded(child: ColoredBox(color: Colors.black)),

        // Capability decides whether the control exists at all.
        if (can.hasRearDisplay)
          StreamBuilder<RearDisplayAvailability>(
            stream: BifoldRearDisplay.availability,
            initialData: RearDisplayAvailability.unresolved,
            builder:
                (
                  BuildContext context,
                  AsyncSnapshot<RearDisplayAvailability> snapshot,
                ) {
                  final RearDisplayAvailability now =
                      snapshot.data ?? RearDisplayAvailability.unresolved;
                  final RearDisplayStatus status = now.presentation;
                  final bool running = status == RearDisplayStatus.active;

                  return SwitchListTile(
                    title: const Text('Show the subject their framing'),
                    subtitle: Text(switch (status) {
                      RearDisplayStatus.active =>
                        'Showing on the outer display',
                      RearDisplayStatus.available => 'Ready to show it',
                      RearDisplayStatus.unavailable =>
                        'Waiting for the camera to start',
                      RearDisplayStatus.unsupported =>
                        now.isResolved
                            ? 'Not available on this device'
                            : 'Checking…',
                    }),
                    // Bound to whether a session is RUNNING, not to whether one
                    // could start. Keying the switch on availability made it snap
                    // back the moment it was flipped, because availability is the
                    // system's answer rather than the app's request.
                    value: running,
                    onChanged: switch (status) {
                      RearDisplayStatus.available ||
                      RearDisplayStatus.active => _toggle,
                      _ => null,
                    },
                  );
                },
          )
        else if (can.statusOf(FoldFeature.rearDisplay) ==
            CapabilityStatus.unknown)
          // Not "no" — "not established". Saying "unsupported" here would be
          // a claim the evidence does not support.
          const ListTile(title: Text('Checking for a second display…'))
        else
          const SizedBox.shrink(),
      ],
    );
  }

  Future<void> _toggle(bool on) async {
    if (on) {
      // False means the system said no, which is not an error. The status
      // stream reports what actually happened, so there is nothing to store.
      await BifoldRearDisplay.present(entrypoint: 'rearDisplayMain');
    } else {
      await BifoldRearDisplay.end();
    }
  }
}
