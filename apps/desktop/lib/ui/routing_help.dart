import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/labels.dart';
import '../state/host_platform.dart';
import '../state/route_check.dart';
import 'adaptive/platform_expander.dart';
import 'theme/tokens.dart';

class RoutingHelp extends ConsumerWidget {
  const RoutingHelp({super.key});

  Widget _topic(BuildContext context, String title, List<String> steps) {
    final pad = context.tokens.cardPadding;
    return PlatformExpander(
      title: title,
      nested: true,
      childrenPadding: EdgeInsets.fromLTRB(pad + 12, 0, pad, 12),
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
    final pad = context.tokens.cardPadding;
    return PlatformExpander(
      icon: Icons.alt_route,
      title: l.routingTitle,
      subtitle: l.routingSubtitle,
      childrenPadding: const EdgeInsets.only(bottom: 12),
      children: [
        _topic(context, l.routingZoomDesktopTitle, [
          l.routingZoom1,
          windows ? l.routingZoom2Windows : l.routingZoom2,
          l.routingZoom3,
          l.routingZoom4,
        ]),
        _topic(context, l.routingWebTitle, [
          l.routingWeb1,
          windows ? l.routingWeb2Windows : l.routingWeb2,
          l.routingWeb3,
        ]),
        _topic(context, l.routingUpworkTitle, [l.routingUpwork1, l.routingUpwork2]),
        _topic(context, l.routingBackTitle, [l.routingBack1, l.routingBack2]),
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
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
