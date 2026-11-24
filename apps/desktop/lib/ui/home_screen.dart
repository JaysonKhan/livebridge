import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/models.dart';
import '../state/route_check.dart';
import '../state/session_state.dart';
import '../state/setup_state.dart';
import 'banners.dart';
import 'consent_dialog.dart';
import 'session_panel.dart';
import 'setup_panel.dart';

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
    final notice = ref.watch(setupProvider.select((s) => s.deviceNotice));
    final scheme = Theme.of(context).colorScheme;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        appBar: AppBar(title: const Text('LiveBridge AI')),
        body: Column(
          children: [
            if (bypass) const BypassBanner(),
            if (mock) const MockBanner(),
            if (error != null)
              StatusBanner(
                icon: Icons.error_outline,
                text: '${error.code}: ${error.message}${error.fatal ? ' (the session ended)' : ''}',
                background: scheme.errorContainer,
                foreground: scheme.onErrorContainer,
                bold: false,
                dismissLabel: 'Dismiss error',
                onDismiss: ref.read(sessionProvider.notifier).dismissError,
              ),
            if (notice != null)
              StatusBanner(
                icon: Icons.usb_off,
                text: notice,
                background: scheme.secondaryContainer,
                foreground: scheme.onSecondaryContainer,
                bold: false,
                dismissLabel: 'Dismiss notice',
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
    final blockers = startBlockers(setup);
    final running = engine != EngineState.idle;
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
              label: const Text('Stop session'),
            )
          else ...[
            FilledButton.icon(
              key: const Key('start-button'),
              onPressed: blockers.isEmpty ? () => _start(context, ref) : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start session'),
            ),
            for (final reason in blockers)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.block, size: 16),
                    const SizedBox(width: 6),
                    Expanded(child: Text(reason, style: Theme.of(context).textTheme.bodySmall)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
