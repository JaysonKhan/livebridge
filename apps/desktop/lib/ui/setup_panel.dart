import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/languages.dart';
import '../bridge/models.dart';
import '../l10n/labels.dart';
import '../state/connection_state.dart';
import '../state/host_platform.dart';
import '../state/providers.dart';
import '../state/route_check.dart';
import '../state/session_state.dart';
import '../state/setup_state.dart';
import 'adaptive/control_border.dart';
import 'adaptive/labeled_field.dart';
import 'adaptive/platform_dropdown.dart';
import 'adaptive/platform_radio.dart';
import 'adaptive/pressable.dart';
import 'analytics_section.dart';
import 'device_test.dart';
import 'routing_help.dart';
import 'theme/tokens.dart';
import 'voices_section.dart';

class SetupPanel extends ConsumerWidget {
  const SetupPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(sessionProvider.select((s) => s.running));
    final l = context.l10n;
    return IgnorePointer(
      ignoring: running,
      child: Opacity(
        opacity: running ? 0.6 : 1,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (running)
              Padding(
                key: const ValueKey('locked-note'),
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(l.setupLocked),
              ),
            const _LanguageAndMode(key: ValueKey('lang')),
            const _DevicesSection(key: ValueKey('devices')),
            const VoicesSection(key: ValueKey('voices')),
            const _MeetingSourceSection(key: ValueKey('source')),
            const _GatewaySection(key: ValueKey('gateway')),
            const Card(key: ValueKey('wizard'), child: DeviceTestSection()),
            const Card(key: ValueKey('routing'), child: RoutingHelp()),
            const Card(key: ValueKey('analytics'), child: AnalyticsSection()),
          ],
        ),
      ),
    );
  }
}

/// A titled settings group. Windows: a Fluent card (card fill and stroke, radius 8, no shadow) with the Body Strong
/// title inside. macOS: the group title above a grouped box, as in System Settings.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final titleRow = Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleMedium!.copyWith(color: t.textPrimary)),
          ),
        ),
        ?trailing,
      ],
    );
    if (t.isWindows) {
      return Card(
        child: Padding(
          padding: EdgeInsets.all(t.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [titleRow, const SizedBox(height: 12), child],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(6, 0, 0, 2), child: titleRow),
          Card(
            child: Padding(padding: EdgeInsets.all(t.cardPadding), child: child),
          ),
        ],
      ),
    );
  }
}

class ChoiceOption<T> {
  const ChoiceOption(this.value, this.title, this.description);
  final T value;
  final String title;
  final String description;
}

/// A single-choice list of platform radio buttons; the selected option is marked by the filled radio and bold
/// text, not by colour alone.
class ChoiceList<T> extends StatelessWidget {
  const ChoiceList({super.key, required this.options, required this.value, required this.onChanged});

  final List<ChoiceOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final o in options) _ChoiceRow(option: o, selected: o.value == value, onTap: () => onChanged(o.value)),
        ],
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.option, required this.selected, required this.onTap});

  final ChoiceOption<Object?> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Semantics(
        checked: selected,
        inMutuallyExclusiveGroup: true,
        child: Pressable(
          onPressed: onTap,
          builder: (context, s) => FocusRing(
            visible: s.focused,
            radius: t.controlRadius,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              decoration: BoxDecoration(
                color: s.pressed ? t.subtleFillPressed : (s.hovered ? t.subtleFill : Colors.transparent),
                borderRadius: BorderRadius.circular(t.controlRadius),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PlatformRadio(selected: selected, hovered: s.hovered, pressed: s.pressed),
                  SizedBox(width: t.isWindows ? 8 : 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          option.title,
                          style: text.bodyMedium!.copyWith(
                            color: t.textPrimary,
                            fontWeight: selected ? FontWeight.w600 : null,
                          ),
                        ),
                        Text(option.description, style: text.bodySmall!.copyWith(color: t.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageAndMode extends ConsumerWidget {
  const _LanguageAndMode({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final modes = [
      ChoiceOption(SessionMode.captions, l.modeCaptionsTitle, l.modeCaptionsDesc),
      ChoiceOption(SessionMode.incoming, l.modeIncomingTitle, l.modeIncomingDesc),
      ChoiceOption(SessionMode.bidirectional, l.modeBidirectionalTitle, l.modeBidirectionalDesc),
    ];
    final myLang = ref.watch(setupProvider.select((s) => s.myLang));
    final theirLang = ref.watch(setupProvider.select((s) => s.targetLang));
    final names = ref.watch(languageNamesProvider(l.localeName)).value ?? const <String, String>{};
    final mode = ref.watch(setupProvider.select((s) => s.mode));
    final notifier = ref.read(setupProvider.notifier);
    return SectionCard(
      title: l.sectionLanguageMode,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // One full-width row each, so long names (Russian, Uzbek) are not cut off.
          _LanguageDropdown(
            key: const Key('my-language'),
            label: l.myLanguage,
            value: myLang,
            systemNames: names,
            onChanged: notifier.setMyLang,
          ),
          const SizedBox(height: 12),
          _LanguageDropdown(
            key: const Key('their-language'),
            label: l.theirLanguage,
            value: theirLang,
            systemNames: names,
            onChanged: notifier.setTargetLang,
          ),
          const SizedBox(height: 12),
          ChoiceList<SessionMode>(options: modes, value: mode, onChanged: notifier.setMode),
        ],
      ),
    );
  }
}

/// One of the session's two languages, from the full list: the four interface languages first, then the rest by
/// name. Typing in the field filters the list.
class _LanguageDropdown extends StatelessWidget {
  const _LanguageDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.systemNames,
    required this.onChanged,
  });

  final String label;
  final String value;
  final Map<String, String> systemNames;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    const first = ['uz', 'en', 'ru', 'tr'];
    final rest = [
      for (final code in kLanguages.keys)
        if (!first.contains(code)) (value: code, label: l.languageName(code, systemNames)),
    ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    final entries = [for (final code in first) (value: code, label: l.languageName(code)), ...rest];
    return LabeledField(
      label: label,
      mergeSemantics: false,
      child: PlatformDropdown<String>(entries: entries, value: value, filter: true, onChanged: onChanged),
    );
  }
}

class _DeviceDropdown extends StatelessWidget {
  const _DeviceDropdown({
    super.key,
    required this.label,
    required this.devices,
    required this.selectedUid,
    required this.onChanged,
  });

  final String label;
  final List<AudioDevice> devices;
  final String? selectedUid;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return LabeledField(
      label: label,
      mergeSemantics: false,
      child: PlatformDropdown<String>(
        entries: [for (final d in devices) (value: d.uid, label: d.name)],
        value: devices.any((d) => d.uid == selectedUid) ? selectedUid : null,
        hint: context.l10n.notSelected,
        onChanged: onChanged,
      ),
    );
  }
}

class _DevicesSection extends ConsumerWidget {
  const _DevicesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(setupProvider);
    final notifier = ref.read(setupProvider.notifier);
    final virtualMic = s.virtualMic;
    final platform = ref.watch(hostPlatformProvider);
    final windows = platform == HostPlatform.windows;
    final l = context.l10n;
    final t = context.tokens;
    return SectionCard(
      title: l.sectionDevices,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DeviceDropdown(
            key: const Key('mic-dropdown'),
            label: l.deviceMicrophone,
            devices: s.inputDevices,
            selectedUid: s.micUid,
            onChanged: notifier.setMic,
          ),
          const SizedBox(height: 12),
          _DeviceDropdown(
            key: const Key('headphones-dropdown'),
            label: l.deviceHeadphones,
            devices: s.outputDevices,
            selectedUid: s.headphonesUid,
            onChanged: notifier.setHeadphones,
          ),
          const SizedBox(height: 12),
          for (final warning in routeWarnings(s, l, platform)) ...[
            _CautionBox(
              icon: Icons.warning_amber_rounded,
              child: Text(warning, style: TextStyle(color: t.textPrimary)),
            ),
            const SizedBox(height: 12),
          ],
          if (virtualMic != null)
            Row(
              // The Windows sentence runs over several lines; the icon stays with the first.
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle_outline, color: t.success.foreground),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(windows ? l.virtualMicFoundWindows(virtualMic.name) : l.virtualMicFound(virtualMic.name)),
                ),
              ],
            )
          else
            _CautionBox(
              key: const Key('blackhole-missing'),
              icon: Icons.info_outline,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    windows ? l.vbCableMissingNotice : l.blackHoleMissingNotice,
                    style: TextStyle(color: t.textPrimary, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    windows ? l.vbCableDownloadFrom(vbCableDownloadUrl) : l.blackHoleInstallWith(blackHoleInstallHint),
                    style: TextStyle(color: t.textPrimary),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A caution-coloured note under the device fields: the missing virtual cable, a device choice to reconsider.
class _CautionBox extends StatelessWidget {
  const _CautionBox({super.key, required this.icon, required this.child});

  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.caution.background,
        borderRadius: BorderRadius.circular(t.isWindows ? t.controlRadius : t.cardRadius - 2),
        border: Border.all(color: t.cardStroke),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: t.caution.foreground),
          const SizedBox(width: 8),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _MeetingSourceSection extends ConsumerWidget {
  const _MeetingSourceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final processes = ref.watch(setupProvider.select((s) => s.processes));
    final selected = ref.watch(setupProvider.select((s) => s.sourcePids));
    final notifier = ref.read(setupProvider.notifier);
    final sorted = [...processes]..sort((a, b) => a.isPlaying == b.isPlaying ? 0 : (a.isPlaying ? -1 : 1));
    final l = context.l10n;
    return SectionCard(
      title: l.sectionMeetingSource,
      trailing: TextButton.icon(
        onPressed: notifier.refreshProcesses,
        icon: const Icon(Icons.refresh),
        label: Text(l.refresh),
      ),
      child: sorted.isEmpty
          ? Text(l.noAudioApps)
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in sorted)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: selected.contains(p.pid),
                      onChanged: (v) => notifier.toggleSource(p.pid, v ?? false),
                      title: Text(p.name),
                      subtitle: Text(l.processPid(p.pid)),
                      secondary: p.isPlaying
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.volume_up, size: 16, color: context.tokens.accentText),
                                const SizedBox(width: 4),
                                Text(l.processPlaying, style: Theme.of(context).textTheme.bodySmall),
                              ],
                            )
                          : null,
                    ),
                ],
              ),
            ),
    );
  }
}

class _GatewaySection extends ConsumerWidget {
  const _GatewaySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final turnModes = [
      ChoiceOption(OutCommit.manual, l.turnPttTitle, l.turnPttDesc),
      ChoiceOption(OutCommit.vad, l.turnVadTitle, l.turnVadDesc),
      ChoiceOption(OutCommit.turnPrediction, l.turnPredictionTitle, l.turnPredictionDesc),
    ];
    final outCommit = ref.watch(setupProvider.select((s) => s.outCommit));
    final model = ref.watch(setupProvider.select((s) => s.translationModel));
    final notifier = ref.read(setupProvider.notifier);
    return SectionCard(
      title: l.sectionGateway,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.outgoingTurnMode, style: Theme.of(context).textTheme.labelLarge),
          ChoiceList<OutCommit>(options: turnModes, value: outCommit, onChanged: notifier.setOutCommit),
          const SizedBox(height: 8),
          const _ConnectionSummary(),
          const SizedBox(height: 12),
          StateTextField(
            key: const Key('translation-model'),
            label: l.translationModelOptional,
            value: model,
            onChanged: notifier.setTranslationModel,
          ),
        ],
      ),
    );
  }
}

/// One line naming how sessions are paid for (the account's e-mail, own keys, or the gateway's address) with a button
/// back to the connection choice.
class _ConnectionSummary extends ConsumerWidget {
  const _ConnectionSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final t = context.tokens;
    final connection = ref.watch(connectionProvider);
    final gatewayUrl = ref.watch(setupProvider.select((s) => s.gatewayUrl)).trim();
    final (icon, text) = switch (connection.mode) {
      ConnectionMode.account => (Icons.person_outline, connection.account?.email ?? l.connectionAccount),
      ConnectionMode.keys => (Icons.key_outlined, l.connectionOwnKeys),
      _ => (Icons.dns_outlined, gatewayUrl.isEmpty ? l.onboardingOwnGateway : gatewayUrl),
    };
    return Row(
      children: [
        Icon(icon, size: 18, color: t.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            key: const Key('connection-summary'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: t.textPrimary),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          key: const Key('connection-change'),
          onPressed: ref.read(connectionProvider.notifier).changeConnection,
          child: Text(l.connectionChange),
        ),
      ],
    );
  }
}

/// A text field backed by state: follows outside changes (settings load) without fighting the user's typing.
class StateTextField extends StatefulWidget {
  const StateTextField({super.key, required this.label, required this.value, required this.onChanged});

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<StateTextField> createState() => _StateTextFieldState();
}

class _StateTextFieldState extends State<StateTextField> {
  late final TextEditingController _controller = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(StateTextField old) {
    super.didUpdateWidget(old);
    if (_controller.text != widget.value) _controller.text = widget.value;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LabeledField(
      label: widget.label,
      child: TextField(
        controller: _controller,
        autocorrect: false,
        onChanged: widget.onChanged,
        style: Theme.of(context).textTheme.bodyLarge!.copyWith(color: context.tokens.textPrimary),
        decoration: const InputDecoration(),
      ),
    );
  }
}
