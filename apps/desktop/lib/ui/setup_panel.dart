import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/models.dart';
import '../state/route_check.dart';
import '../state/session_state.dart';
import '../state/setup_state.dart';
import 'device_test.dart';
import 'routing_help.dart';

class SetupPanel extends ConsumerWidget {
  const SetupPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(sessionProvider.select((s) => s.running));
    return IgnorePointer(
      ignoring: running,
      child: Opacity(
        opacity: running ? 0.6 : 1,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (running)
              const Padding(
                key: ValueKey('locked-note'),
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Setup is locked while a session is running.'),
              ),
            const _LanguageAndMode(key: ValueKey('lang')),
            const _DevicesSection(key: ValueKey('devices')),
            const _MeetingSourceSection(key: ValueKey('source')),
            const _GatewaySection(key: ValueKey('gateway')),
            const Card(key: ValueKey('wizard'), child: DeviceTestSection()),
            const Card(key: ValueKey('routing'), child: RoutingHelp()),
          ],
        ),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
                ?trailing,
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
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

/// A single-choice list; the selected option is marked by an icon and bold text, not by colour alone.
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
        children: [
          for (final o in options)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              selected: o.value == value,
              leading: Icon(o.value == value ? Icons.radio_button_checked : Icons.radio_button_unchecked),
              title: Text(o.title, style: TextStyle(fontWeight: o.value == value ? FontWeight.bold : null)),
              subtitle: Text(o.description),
              onTap: () => onChanged(o.value),
            ),
        ],
      ),
    );
  }
}

class _LanguageAndMode extends ConsumerWidget {
  const _LanguageAndMode({super.key});

  static const _modes = [
    ChoiceOption(SessionMode.captions, 'Captions only', 'Live captions both ways. Nothing is spoken.'),
    ChoiceOption(
      SessionMode.incoming,
      'Incoming audio',
      'Captions both ways, plus their speech translated into Uzbek in your headphones.',
    ),
    ChoiceOption(
      SessionMode.bidirectional,
      'Bidirectional speech',
      'Also speaks your translation into the call with your own voice, through the virtual microphone.',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(setupProvider.select((s) => s.targetLang));
    final mode = ref.watch(setupProvider.select((s) => s.mode));
    final notifier = ref.read(setupProvider.notifier);
    return SectionCard(
      title: 'Language and mode',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Uzbek ↔ English'),
                selected: lang == TargetLang.en,
                onSelected: (_) => notifier.setTargetLang(TargetLang.en),
              ),
              ChoiceChip(
                label: const Text('Uzbek ↔ Russian'),
                selected: lang == TargetLang.ru,
                onSelected: (_) => notifier.setTargetLang(TargetLang.ru),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ChoiceList<SessionMode>(options: _modes, value: mode, onChanged: notifier.setMode),
        ],
      ),
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
    final value = devices.any((d) => d.uid == selectedUid) ? selectedUid : null;
    return InputDecorator(
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          isDense: true,
          value: value,
          hint: const Text('Not selected'),
          items: [
            for (final d in devices)
              DropdownMenuItem(
                value: d.uid,
                child: Text(d.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged,
        ),
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
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      title: 'Devices',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DeviceDropdown(
            key: const Key('mic-dropdown'),
            label: 'Microphone',
            devices: s.inputDevices,
            selectedUid: s.micUid,
            onChanged: notifier.setMic,
          ),
          const SizedBox(height: 12),
          _DeviceDropdown(
            key: const Key('headphones-dropdown'),
            label: 'Headphones',
            devices: s.outputDevices,
            selectedUid: s.headphonesUid,
            onChanged: notifier.setHeadphones,
          ),
          const SizedBox(height: 12),
          if (virtualMic != null)
            Row(
              children: [
                const Icon(Icons.check_circle_outline),
                const SizedBox(width: 8),
                Expanded(child: Text('Virtual microphone: ${virtualMic.name} found')),
              ],
            )
          else
            Container(
              key: const Key('blackhole-missing'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(8)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: scheme.onTertiaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          blackHoleMissingNotice,
                          style: TextStyle(color: scheme.onTertiaryContainer, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          'Install it with: $blackHoleInstallHint',
                          style: TextStyle(color: scheme.onTertiaryContainer),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
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
    return SectionCard(
      title: 'Meeting source',
      trailing: TextButton.icon(
        onPressed: notifier.refreshProcesses,
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh'),
      ),
      child: sorted.isEmpty
          ? const Text('No apps are using audio right now. Open your meeting app, then press Refresh.')
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
                      subtitle: Text('pid ${p.pid}'),
                      secondary: p.isPlaying
                          ? const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [Icon(Icons.volume_up, size: 18), SizedBox(width: 4), Text('playing')],
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

  static const _turnModes = [
    ChoiceOption(OutCommit.manual, 'Push-to-talk', 'Hold the button or the Space key while you speak.'),
    ChoiceOption(OutCommit.vad, 'Auto: VAD', 'Sends your speech when you pause.'),
    ChoiceOption(OutCommit.turnPrediction, 'Auto: turn prediction', 'Predicts when you have finished a thought.'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outCommit = ref.watch(setupProvider.select((s) => s.outCommit));
    final gatewayUrl = ref.watch(setupProvider.select((s) => s.gatewayUrl));
    final token = ref.watch(setupProvider.select((s) => s.accessToken));
    final model = ref.watch(setupProvider.select((s) => s.translationModel));
    final notifier = ref.read(setupProvider.notifier);
    return SectionCard(
      title: 'Outgoing turns and gateway',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Outgoing turn mode', style: Theme.of(context).textTheme.labelLarge),
          ChoiceList<OutCommit>(options: _turnModes, value: outCommit, onChanged: notifier.setOutCommit),
          const SizedBox(height: 8),
          StateTextField(
            key: const Key('gateway-url'),
            label: 'Gateway URL',
            value: gatewayUrl,
            onChanged: notifier.setGatewayUrl,
          ),
          const SizedBox(height: 12),
          StateTextField(
            key: const Key('access-token'),
            label: 'Access token',
            value: token,
            obscure: true,
            onChanged: notifier.setAccessToken,
          ),
          const SizedBox(height: 12),
          StateTextField(
            key: const Key('translation-model'),
            label: 'Translation model (optional)',
            value: model,
            onChanged: notifier.setTranslationModel,
          ),
        ],
      ),
    );
  }
}

/// A text field backed by state: follows outside changes (settings load) without fighting the user's typing.
class StateTextField extends StatefulWidget {
  const StateTextField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.obscure = false,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool obscure;

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
    return TextField(
      controller: _controller,
      obscureText: widget.obscure,
      autocorrect: false,
      enableSuggestions: !widget.obscure,
      onChanged: widget.onChanged,
      decoration: InputDecoration(labelText: widget.label, border: const OutlineInputBorder(), isDense: true),
    );
  }
}
