import 'package:flutter/material.dart';

import '../l10n/labels.dart';
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
    final l = context.l10n;
    return ExpansionTile(
      leading: const Icon(Icons.alt_route),
      title: Text(l.routingTitle),
      subtitle: Text(l.routingSubtitle),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: [
        _topic(l.routingZoomDesktopTitle, [l.routingZoom1, l.routingZoom2, l.routingZoom3, l.routingZoom4]),
        _topic(l.routingWebTitle, [l.routingWeb1, l.routingWeb2, l.routingWeb3]),
        _topic(l.routingUpworkTitle, [l.routingUpwork1, l.routingUpwork2]),
        _topic(l.routingBackTitle, [l.routingBack1, l.routingBack2]),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(l.routingInstallVirtual(blackHoleInstallHint)),
          ),
        ),
      ],
    );
  }
}
