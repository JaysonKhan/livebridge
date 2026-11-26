import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/labels.dart';
import '../state/connection_state.dart';
import '../state/setup_state.dart';
import 'adaptive/control_border.dart';
import 'adaptive/pressable.dart';
import 'theme/tokens.dart';
import 'top_up_sheet.dart';

/// The header chip beside the language picker. With an account: the e-mail's first letter and about how many minutes
/// the balance lasts in the chosen mode, with a menu (Top up, Account page, Sign out). With own keys or an own
/// gateway: the name of the mode, with a menu to change the connection.
class AccountChip extends ConsumerWidget {
  const AccountChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(connectionProvider);
    final mode = connection.mode;
    if (mode == null) return const SizedBox.shrink();
    final sessionMode = ref.watch(setupProvider.select((s) => s.mode));
    final notifier = ref.read(connectionProvider.notifier);
    final l = context.l10n;
    final t = context.tokens;

    final Widget leading;
    final String label;
    final List<(String, VoidCallback)> items;
    switch (mode) {
      case ConnectionMode.account:
        final email = connection.account?.email.trim() ?? '';
        final minutes = connection.minutesLeft(sessionMode);
        leading = _Avatar(email.isEmpty ? null : email.characters.first.toUpperCase());
        label = minutes == null ? '' : l.chipMinutes(minutes);
        items = [
          (l.topUp, () => showTopUpSheet(context)),
          (l.accountPage, notifier.openAccountPage),
          (l.signOut, notifier.signOut),
        ];
      case ConnectionMode.keys:
        leading = Icon(Icons.key_outlined, size: 16, color: t.textSecondary);
        label = l.connectionOwnKeys;
        items = [(l.changeConnection, notifier.changeConnection)];
      case ConnectionMode.gateway:
        leading = Icon(Icons.dns_outlined, size: 16, color: t.textSecondary);
        label = l.onboardingOwnGateway;
        items = [(l.changeConnection, notifier.changeConnection)];
    }

    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      menuChildren: [for (final (text, action) in items) MenuItemButton(onPressed: action, child: Text(text))],
      builder: (context, controller, _) => MergeSemantics(
        child: Semantics(
          button: true,
          label: label,
          child: Pressable(
            onPressed: () => controller.isOpen ? controller.close() : controller.open(),
            builder: (context, s) => FocusRing(
              visible: s.focused,
              radius: t.controlRadius,
              child: Container(
                key: const Key('account-chip'),
                height: t.controlHeight,
                constraints: const BoxConstraints(maxWidth: 260),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: s.pressed ? t.subtleFillPressed : (s.hovered ? t.subtleFill : Colors.transparent),
                  borderRadius: BorderRadius.circular(t.controlRadius),
                  border: Border.all(color: t.cardStroke),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    leading,
                    if (label.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: ExcludeSemantics(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: t.textPrimary),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    Icon(t.isWindows ? Icons.keyboard_arrow_down : Icons.unfold_more, size: 16, color: t.textSecondary),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small accent circle with a letter; a person icon while the e-mail is not known (the site has not answered yet).
class _Avatar extends StatelessWidget {
  const _Avatar(this.letter);

  final String? letter;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle),
      child: letter == null
          ? Icon(Icons.person, size: 12, color: t.onAccent)
          : Text(
              letter!,
              style: Theme.of(context).textTheme.labelSmall!
                  .copyWith(color: t.onAccent, fontWeight: FontWeight.w600, height: 1),
            ),
    );
  }
}
