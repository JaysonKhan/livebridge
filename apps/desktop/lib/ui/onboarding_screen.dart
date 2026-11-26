import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/labels.dart';
import '../state/connection_state.dart';
import '../state/setup_state.dart';
import 'adaptive/labeled_field.dart';
import 'adaptive/platform_expander.dart';
import 'adaptive/platform_header.dart';
import 'banners.dart';
import 'google_button.dart';
import 'language_picker.dart';
import 'theme/tokens.dart';

/// The first screen, while no way of paying for sessions is chosen: one obvious action (sign in with Google), with
/// the own-keys and own-gateway choices folded away under it.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _Group { keys, gateway, back }

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _contentWidth = 440.0;

  // After "Change", the saved keys and token are filled in (hidden), so going on with them needs no typing.
  late final _elevenlabs = TextEditingController(text: ref.read(connectionProvider.notifier).savedKeys.elevenlabs);
  late final _gemini = TextEditingController(text: ref.read(connectionProvider.notifier).savedKeys.gemini);
  late final _gatewayUrl = TextEditingController(text: ref.read(setupProvider).gatewayUrl);
  late final _gatewayToken = TextEditingController(text: ref.read(setupProvider).accessToken);

  /// The address and the token are only replaced by the saved ones while the person has not typed in them.
  bool _urlEdited = false;
  bool _tokenEdited = false;
  bool _saving = false;
  _Group? _failed;

  @override
  void dispose() {
    _elevenlabs.dispose();
    _gemini.dispose();
    _gatewayUrl.dispose();
    _gatewayToken.dispose();
    super.dispose();
  }

  bool _filled(TextEditingController a, TextEditingController b) =>
      a.text.trim().isNotEmpty && b.text.trim().isNotEmpty;

  Future<void> _save(_Group group, Future<void> Function() save) async {
    setState(() {
      _saving = true;
      _failed = null;
    });
    try {
      await save();
    } on PlatformException {
      if (mounted) setState(() => _failed = group);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _saveKeys() => _save(
    _Group.keys,
    () => ref.read(connectionProvider.notifier).saveKeys(_elevenlabs.text.trim(), _gemini.text.trim()),
  );

  void _saveGateway() => _save(
    _Group.gateway,
    () => ref.read(connectionProvider.notifier).saveGateway(_gatewayUrl.text.trim(), _gatewayToken.text.trim()),
  );

  void _back() => _save(_Group.back, ref.read(connectionProvider.notifier).restorePrevious);

  void _gatewayOpened(bool open) {
    if (!open) return;
    final saved = ref.read(setupProvider);
    if (!_urlEdited) _gatewayUrl.text = saved.gatewayUrl;
    if (!_tokenEdited) _gatewayToken.text = saved.accessToken;
  }

  @override
  Widget build(BuildContext context) {
    final signIn = ref.watch(connectionProvider.select((s) => s.signIn));
    final notice = ref.watch(connectionProvider.select((s) => s.notice));
    final canGoBack = ref.watch(connectionProvider.select((s) => s.previous)) != null;
    final l = context.l10n;
    final notifier = ref.read(connectionProvider.notifier);
    final text = Theme.of(context).textTheme;
    final t = context.tokens;

    final String? problem = switch (signIn) {
      SignInFailed(:final reason) => switch (reason) {
        'expired' => l.signInExpired,
        'denied' => l.signInDenied,
        'rate_limited' => l.signInRateLimited,
        _ => l.signInNetwork,
      },
      _ => null,
    };

    final Widget body;
    if (signIn is SignInWaiting) {
      body = Column(
        key: const Key('sign-in-waiting'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.signInWaitingTitle,
            textAlign: TextAlign.center,
            style: text.titleLarge!.copyWith(color: t.textPrimary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            l.signInWaitingHint,
            textAlign: TextAlign.center,
            style: text.bodyMedium!.copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: 20),
          Center(
            child: SelectableText(
              signIn.userCode,
              key: const Key('sign-in-code'),
              style: text.headlineMedium!.copyWith(
                color: t.textPrimary,
                fontWeight: FontWeight.w600,
                letterSpacing: 3,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (signIn.openFailed) ...[
            const SizedBox(height: 16),
            Text(
              l.signInOpenManually,
              textAlign: TextAlign.center,
              style: text.bodyMedium!.copyWith(color: t.textSecondary),
            ),
            const SizedBox(height: 4),
            SelectableText(
              '${signIn.page}',
              key: const Key('sign-in-address'),
              textAlign: TextAlign.center,
              style: text.bodyMedium!.copyWith(color: t.textPrimary),
            ),
          ],
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton(onPressed: notifier.openPageAgain, child: Text(l.signInOpenAgain)),
              TextButton(onPressed: notifier.cancelSignIn, child: Text(l.cancel)),
            ],
          ),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (canGoBack) ...[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const Key('onboarding-back'),
                onPressed: _saving ? null : _back,
                icon: const Icon(Icons.arrow_back, size: 16),
                label: Text(l.onboardingBack),
              ),
            ),
            if (_failed == _Group.back)
              Text(l.onboardingSaveFailed, style: text.bodySmall!.copyWith(color: t.critical.foreground)),
            const SizedBox(height: 8),
          ],
          Text(
            l.onboardingTitle,
            textAlign: TextAlign.center,
            style: text.headlineSmall!.copyWith(color: t.textPrimary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            l.onboardingSubtitle,
            textAlign: TextAlign.center,
            style: text.bodyLarge!.copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: 24),
          if (problem != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: StatusBanner(
                icon: Icons.error_outline,
                text: problem,
                severity: StatusSeverity.critical,
                bold: false,
              ),
            )
          else if (notice == 'signed_out')
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: StatusBanner(
                icon: Icons.info_outline,
                text: l.noticeSignedOut,
                severity: StatusSeverity.caution,
                bold: false,
              ),
            ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: GoogleButton(onPressed: notifier.beginSignIn),
            ),
          ),
          const SizedBox(height: 20),
          Card(child: _keysSection(context)),
        ],
      );
    }

    return Scaffold(
      body: Column(
        children: [
          const PlatformHeader(trailing: LanguagePicker()),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: _contentWidth),
                      child: Padding(padding: const EdgeInsets.all(24), child: body),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _keysSection(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    return PlatformExpander(
      title: l.onboardingOwnKeys,
      childrenPadding: EdgeInsets.fromLTRB(t.cardPadding, 0, t.cardPadding, t.cardPadding),
      children: [
        _SecretField(key: const Key('elevenlabs-key'), label: l.elevenlabsKey, controller: _elevenlabs),
        const SizedBox(height: 12),
        _SecretField(key: const Key('gemini-key'), label: l.geminiKey, controller: _gemini),
        const SizedBox(height: 12),
        _saveRow(
          context,
          buttonKey: const Key('keys-save'),
          group: _Group.keys,
          fields: Listenable.merge([_elevenlabs, _gemini]),
          ready: () => _filled(_elevenlabs, _gemini),
          onPressed: _saveKeys,
        ),
        const SizedBox(height: 8),
        // The own gateway is folded inside, so the first view stays one choice.
        PlatformExpander(
          nested: true,
          title: l.onboardingOwnGateway,
          onExpansionChanged: _gatewayOpened,
          childrenPadding: EdgeInsets.fromLTRB(t.cardPadding, 4, t.cardPadding, t.cardPadding),
          children: [
            LabeledField(
              label: l.gatewayUrl,
              child: TextField(
                key: const Key('onboarding-gateway-url'),
                controller: _gatewayUrl,
                autocorrect: false,
                onChanged: (_) => _urlEdited = true,
                style: Theme.of(context).textTheme.bodyLarge!.copyWith(color: t.textPrimary),
              ),
            ),
            const SizedBox(height: 12),
            _SecretField(
              key: const Key('onboarding-gateway-token'),
              label: l.accessToken,
              controller: _gatewayToken,
              onChanged: (_) => _tokenEdited = true,
            ),
            const SizedBox(height: 12),
            _saveRow(
              context,
              buttonKey: const Key('gateway-save'),
              group: _Group.gateway,
              fields: Listenable.merge([_gatewayUrl, _gatewayToken]),
              ready: () => _filled(_gatewayUrl, _gatewayToken),
              onPressed: _saveGateway,
            ),
          ],
        ),
      ],
    );
  }

  /// "Save and continue" (off while a field of its group is empty) with the save failure, if any, above it.
  Widget _saveRow(
    BuildContext context, {
    required Key buttonKey,
    required _Group group,
    required Listenable fields,
    required bool Function() ready,
    required VoidCallback onPressed,
  }) {
    final l = context.l10n;
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_failed == group)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              l.onboardingSaveFailed,
              style: Theme.of(context).textTheme.bodySmall!.copyWith(color: t.critical.foreground),
            ),
          ),
        ListenableBuilder(
          listenable: fields,
          builder: (context, _) => Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton(
              key: buttonKey,
              onPressed: ready() && !_saving ? onPressed : null,
              child: Text(l.saveAndContinue),
            ),
          ),
        ),
      ],
    );
  }
}

/// A key or token field: hidden as typed, with a button that shows it for a moment.
class _SecretField extends StatefulWidget {
  const _SecretField({super.key, required this.label, required this.controller, this.onChanged});

  final String label;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  @override
  State<_SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<_SecretField> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.tokens;
    final tip = _shown ? l.hideSecret : l.showSecret;
    return LabeledField(
      label: widget.label,
      child: TextField(
        controller: widget.controller,
        onChanged: widget.onChanged,
        obscureText: !_shown,
        autocorrect: false,
        enableSuggestions: false,
        style: Theme.of(context).textTheme.bodyLarge!.copyWith(color: t.textPrimary),
        decoration: InputDecoration(
          suffixIcon: IconButton(
            tooltip: tip,
            iconSize: 16,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: BoxConstraints.tightFor(width: t.controlHeight, height: t.controlHeight),
            icon: Icon(_shown ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: t.textSecondary),
            onPressed: () => setState(() => _shown = !_shown),
          ),
          suffixIconConstraints: BoxConstraints.tightFor(width: t.controlHeight, height: t.controlHeight),
        ),
      ),
    );
  }
}
