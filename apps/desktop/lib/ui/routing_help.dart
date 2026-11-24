import 'package:flutter/material.dart';

import '../state/route_check.dart';

class RoutingHelp extends StatelessWidget {
  const RoutingHelp({super.key});

  Widget _topic(String title, List<String> steps) {
    return ExpansionTile(
      title: Text(title),
      dense: true,
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('${i + 1}. ${steps[i]}')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: const Icon(Icons.alt_route),
      title: const Text('Routing instructions'),
      subtitle: const Text('How to set up Zoom, Meet and Upwork'),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: [
        _topic('Zoom Desktop', const [
          'Open Zoom → Settings → Audio.',
          'Microphone: BlackHole 2ch.',
          'Speaker: your headphones.',
          'Start the session here before you speak.',
        ]),
        _topic('Zoom Web / Google Meet', const [
          "Open the browser's audio settings for the call.",
          'Microphone: BlackHole 2ch. Speaker: your headphones.',
          'Use a dedicated browser window and close other tabs that play audio.',
        ]),
        _topic('Upwork', const [
          'Start the call from Upwork Messages.',
          'Then use the same Zoom Desktop or browser settings as above.',
        ]),
        _topic('How to return to normal', const [
          'In the meeting app, select your physical microphone again.',
          'Stop the session here.',
        ]),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SelectableText('Install the virtual microphone: $blackHoleInstallHint'),
          ),
        ),
      ],
    );
  }
}
