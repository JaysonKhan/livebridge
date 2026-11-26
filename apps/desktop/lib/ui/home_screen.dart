import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/models.dart';
import '../l10n/labels.dart';
import '../state/connection_state.dart';
import '../state/host_platform.dart';
import '../state/route_check.dart';
import '../state/session_state.dart';
import '../state/setup_state.dart';
import 'account_chip.dart';
import 'adaptive/platform_header.dart';
import 'banners.dart';
import 'consent_dialog.dart';
import 'language_picker.dart';
import 'session_panel.dart';
import 'setup_panel.dart';
import 'theme/tokens.dart';
import 'top_up_sheet.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _focus = FocusNode(debugLabel: 'home');

  /// Back from the browser after a purchase (or after the site could not be reached at launch): read the balance
  /// again.
  late final AppLifecycleListener _lifecycle;

  void _refreshAccount() {
    if (ref.read(connectionProvider).mode == ConnectionMode.account) {
      unawaited(ref.read(connectionProvider.notifier).refreshAccount());
    }
  }

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refreshAccount);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
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
            const PlatformHeader(
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [AccountChip(), SizedBox(width: 8), LanguagePicker()],
              ),
            ),
            if (bypass) const BypassBanner(),
            if (mock) const MockBanner(),
            if (error != null) _ErrorStrip(error),
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
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: setupColumnWidth(constraints.maxWidth), child: const _SetupColumn()),
                    const VerticalDivider(width: 1),
                    const Expanded(child: SessionPanel()),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Starts a session after the other participants agreed (the consent dialog).
Future<void> _startWithConsent(BuildContext context, WidgetRef ref) async {
  final agreed = await showConsentDialog(context);
  if (!agreed || !context.mounted) return;
  await ref
      .read(connectionProvider.notifier)
      .start(ref.read(setupProvider).toConfig(ref.read(connectionProvider).mode));
}

/// The strip under the header for the last session error. The codes people can act on get their own sentence (and a
/// button); the rest show the code with its localized sentence, or the engine's message for a code the app does not
/// know.
class _ErrorStrip extends ConsumerWidget {
  const _ErrorStrip(this.error);

  final ErrorEvent error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final connection = ref.watch(connectionProvider.select((s) => s.mode));
    final account = connection == ConnectionMode.account;
    // On the hosted service a full house means it is busy; an own gateway keeps its own sentence (it already has a
    // session).
    final hosted = account || connection == ConnectionMode.keys;
    final dismiss = ref.read(sessionProvider.notifier).dismissError;
    StatusBanner banner(IconData icon, String text, StatusSeverity severity, [Widget? action]) => StatusBanner(
      icon: icon,
      text: text,
      severity: severity,
      bold: false,
      action: action,
      dismissLabel: l.dismissError,
      onDismiss: dismiss,
    );
    switch (error.code) {
      case 'balance_empty' || 'balance_exhausted':
        return banner(
          Icons.account_balance_wallet_outlined,
          l.bannerBalanceEmpty,
          StatusSeverity.caution,
          account
              ? FilledButton(
                  key: const Key('banner-top-up'),
                  onPressed: () => showTopUpSheet(context),
                  child: Text(l.topUp),
                )
              : null,
        );
      case 'billing_unavailable':
        return banner(Icons.cloud_off_outlined, l.bannerBillingUnavailable, StatusSeverity.critical);
      case 'idle_timeout':
        final connectionState = ref.watch(connectionProvider);
        final blocked =
            connectionState.startPending ||
            startBlockers(
              ref.watch(setupProvider),
              l,
              ref.watch(hostPlatformProvider),
              connection: connectionState,
            ).isNotEmpty;
        return banner(
          Icons.timer_off_outlined,
          l.bannerIdleTimeout,
          StatusSeverity.caution,
          FilledButton(
            key: const Key('banner-start'),
            onPressed: blocked ? null : () => _startWithConsent(context, ref),
            child: Text(l.startSession),
          ),
        );
      case 'session_replaced':
        return banner(Icons.devices_outlined, l.bannerSessionReplaced, StatusSeverity.caution);
      case 'session_limit' when hosted:
        return banner(Icons.hourglass_empty, l.bannerSessionLimit, StatusSeverity.caution);
    }
    final sentence = l.errorMessage(error.code, ref.watch(hostPlatformProvider), connection: connection);
    return banner(
      Icons.error_outline,
      '${error.code}: ${sentence ?? error.message}'
      '${error.fatal ? ' ${l.errorSessionEnded}' : ''}',
      StatusSeverity.critical,
    );
  }
}

/// The setup column: 400 px in the default window, growing with the window (a quarter of it) up to 480 px on large
/// screens.
double setupColumnWidth(double windowWidth) => (windowWidth / 4).clamp(400, 480);

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(sessionProvider.select((s) => s.engine));
    final setup = ref.watch(setupProvider);
    final connection = ref.watch(connectionProvider);
    final l = context.l10n;
    final blockers = startBlockers(setup, l, ref.watch(hostPlatformProvider), connection: connection);
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
              // Off while a Start gets its token, so a second press cannot start a second session.
              onPressed: blockers.isEmpty && !connection.startPending ? () => _startWithConsent(context, ref) : null,
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
