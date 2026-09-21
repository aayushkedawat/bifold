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
/// Collapsing any two of those would produce a UI that lies. A device that
/// *can* do this still shows nothing until a capture session is live, and a
/// control that appears and vanishes with availability would flicker.
class RearDisplayCamera extends StatelessWidget {
  /// Creates the camera screen.
  const RearDisplayCamera({super.key});

  @override
  Widget build(BuildContext context) {
    final BifoldCapabilities can = Bifold.capabilitiesOf(context);

    return Column(
      children: <Widget>[
        const Expanded(child: ColoredBox(color: Colors.black)),

        // Capability decides whether the control exists at all. It is stable
        // for the lifetime of the app, so nothing here flickers.
        if (can.hasRearDisplay)
          StreamBuilder<bool>(
            stream: BifoldCaptureAccessory.availability,
            initialData: false,
            builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
              // Availability decides whether it is enabled. It moves with the
              // capture session, so the control dims rather than disappearing.
              final bool availableNow = snapshot.data ?? false;
              return SwitchListTile(
                title: const Text('Show the subject their framing'),
                subtitle: Text(
                  availableNow
                      ? 'The system is ready to show it'
                      : 'Waiting for the camera to start',
                ),
                value: availableNow,
                onChanged: availableNow
                    ? (bool on) => BifoldCaptureAccessory.setEnabled(on)
                    : null,
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
}
