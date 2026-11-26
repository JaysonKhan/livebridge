import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/models.dart';
import '../l10n/labels.dart';
import '../state/host_platform.dart';
import '../state/route_check.dart';
import '../state/session_state.dart';
import '../state/setup_state.dart';
import 'adaptive/platform_header.dart';
import 'banners.dart';
import 'consent_dialog.dart';
import 'language_picker.dart';
import 'session_panel.dart';
import 'setup_panel.dart';
import 'theme/tokens.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _focus = FocusNode(debugLabel: 'home');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// True when the focused node is, or wraps, a text input (so Space must type a space).
  bool _textFieldFocused() {
    final primary = FocusManager.instance.primaryFocus;
    final context = primary?.context;
    if (primary == null || primary == _focus || context == null) return false;
    var found = context.findAncestorWidgetOfExactType<EditableText>() != null;
    void visit(Element e) {
      if (found) return;
      if (e.widget is EditableText) {
        found = true;
        return;
      }
      e.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return found || context.widget is EditableText;
  }

  /// Space = push-to-talk, Escape = panic. Key repeats never send duplicates.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final session = ref.read(sessionProvider.notifier);
    final held = ref.read(sessionProvider).pttHeld;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (event is KeyDownEvent && ref.read(sessionProvider).running) {
        session.panic();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event.logicalKey != LogicalKeyboardKey.space) return KeyEventResult.ignored;
    switch (event) {
      case KeyDownEvent():
        if (_textFieldFocused() || !ref.read(pttEnabledProvider)) return KeyEventResult.ignored;
        session.pttDown();
        return KeyEventResult.handled;
      case KeyRepeatEvent():
        return held ? KeyEventResult.handled : KeyEventResult.ignored;
      case KeyUpEvent():
        if (!held) return KeyEventResult.ignored;
        session.pttUp();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final mock = ref.watch(sessionProvider.select((s) => s.mock));
    final bypass = ref.watch(sessionProvider.select((s) => s.bypass));
    final error = ref.watch(sessionProvider.select((s) => s.error));
    final lostDevices = ref.watch(setupProvider.select((s) => s.lostDevices));
    final l = context.l10n;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        body: Column(
          children: [
            const PlatformHeader(trailing: LanguagePicker()),
            if (bypass) const BypassBanner(),
            if (mock) const MockBanner(),
            if (error != null)
              StatusBanner(
                icon: Icons.error_outline,
                text:
                    '${error.code}: ${l.errorMessage(error.code, ref.watch(hostPlatformProvider)) ?? error.message}'
                    '${error.fatal ? ' ${l.errorSessionEnded}' : ''}',
                severity: StatusSeverity.critical,
                bold: false,
                dismissLabel: l.dismissError,
                onDismiss: ref.read(sessionProvider.notifier).dismissError,
              ),
            if (lostDevices.isNotEmpty)
              StatusBanner(
                icon: Icons.usb_off,
                text: lostDevices
                    .map(
                      (d) => d.kind == LostDeviceKind.microphone
                          ? l.noticeMicLost(d.name)
                          : l.noticeHeadphonesLost(d.name),
                    )
                    .join('\n'),
                severity: StatusSeverity.caution,
                bold: false,
                dismissLabel: l.dismissNotice,
                onDismiss: ref.read(setupProvider.notifier).dismissNotice,
              ),
            const Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 400, child: _SetupColumn()),
                  VerticalDivider(width: 1),
                  Expanded(child: SessionPanel()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The setup panel with the Start/Stop footer pinned below it.
class _SetupColumn extends StatelessWidget {
  const _SetupColumn();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Expanded(child: SetupPanel()),
        Divider(height: 1),
        _StartFooter(),
      ],
    );
  }
}

class _StartFooter extends ConsumerWidget {
  const _StartFooter();

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    final agreed = await showConsentDialog(context);
    if (!agreed || !context.mounted) return;
    await ref.read(sessionProvider.notifier).start(ref.read(setupProvider).toConfig());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(sessionProvider.select((s) => s.engine));
    final setup = ref.watch(setupProvider);
    final l = context.l10n;
    final blockers = startBlockers(setup, l, ref.watch(hostPlatformProvider));
    final running = engine != EngineState.idle;
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (running)
            FilledButton.icon(
              key: const Key('stop-button'),
              onPressed: engine == EngineState.stopping ? null : ref.read(sessionProvider.notifier).stop,
              icon: const Icon(Icons.stop),
              label: Text(l.stopSession),
            )
          else ...[
            FilledButton.icon(
              key: const Key('start-button'),
              onPressed: blockers.isEmpty ? () => _start(context, ref) : null,
              icon: const Icon(Icons.play_arrow),
              label: Text(l.startSession),
            ),
            for (final reason in blockers)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.block, size: 14, color: t.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        reason,
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(color: t.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
