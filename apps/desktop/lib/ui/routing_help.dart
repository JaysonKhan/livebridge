import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/labels.dart';
import '../state/host_platform.dart';
import '../state/route_check.dart';

class RoutingHelp extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final windows = ref.watch(hostPlatformProvider) == HostPlatform.windows;
    return ExpansionTile(
      leading: const Icon(Icons.alt_route),
      title: Text(l.routingTitle),
      subtitle: Text(l.routingSubtitle),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: [
        _topic(l.routingZoomDesktopTitle, [
          l.routingZoom1,
          windows ? l.routingZoom2Windows : l.routingZoom2,
          l.routingZoom3,
          l.routingZoom4,
        ]),
        _topic(l.routingWebTitle, [l.routingWeb1, windows ? l.routingWeb2Windows : l.routingWeb2, l.routingWeb3]),
        _topic(l.routingUpworkTitle, [l.routingUpwork1, l.routingUpwork2]),
        _topic(l.routingBackTitle, [l.routingBack1, l.routingBack2]),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              windows
                  ? l.routingInstallVirtualWindows(vbCableDownloadUrl)
                  : l.routingInstallVirtual(blackHoleInstallHint),
            ),
          ),
        ),
      ],
    );
  }
}
