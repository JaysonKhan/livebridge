import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/live_bridge.dart';
import '../state/providers.dart';
import '../state/session_state.dart';
import '../state/setup_state.dart';

/// Device test "wizard": level meters, test tones and microphone permission. Never joins a meeting.
class DeviceTestSection extends ConsumerStatefulWidget {
  const DeviceTestSection({super.key});

  @override
  ConsumerState<DeviceTestSection> createState() => _DeviceTestSectionState();
}

class _DeviceTestSectionState extends ConsumerState<DeviceTestSection> {
  final _tile = ExpansibleController();
  late final LiveBridge _bridge = ref.read(bridgeProvider);
  bool _open = false;

  void _startMeters() {
    final s = ref.read(setupProvider);
    ref.read(sessionProvider.notifier).clearMeters();
    unawaited(
      ref
          .read(sessionProvider.notifier)
          .guard('startMeters', () => _bridge.startMeters(micUid: s.micUid, sourcePids: s.sourcePids.toList())),
    );
  }

  void _onExpansion(bool open) {
    if (open == _open) return;
    _open = open;
    if (open) {
      _startMeters();
    } else {
      unawaited(ref.read(sessionProvider.notifier).guard('stopMeters', _bridge.stopMeters));
    }
  }

  @override
  void dispose() {
    if (_open) unawaited(_bridge.stopMeters().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = ref.watch(sessionProvider.select((s) => s.running));
    // A new session stops the meters (the session notifier calls stopMeters); just fold the section.
    ref.listen(sessionProvider.select((s) => s.running), (_, running) {
      if (running && _open) {
        _open = false;
        _tile.collapse();
      }
    });
    // Re-point the meters when the selection changes while the section is open.
    ref.listen(setupProvider.select((s) => (s.micUid, s.sourcePids)), (_, _) {
      if (_open) _startMeters();
    });
    return ExpansionTile(
      controller: _tile,
      enabled: !running,
      leading: const Icon(Icons.tune),
      title: const Text('Test your devices'),
      subtitle: Text(running ? 'Not available while a session is running' : 'Level meters, test tones, permission'),
      onExpansionChanged: _onExpansion,
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: const [_Meters(), SizedBox(height: 12), _Tones(), SizedBox(height: 12), _Permission()],
    );
  }
}

class _Meters extends ConsumerWidget {
  const _Meters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meters = ref.watch(sessionProvider.select((s) => s.meters));
    return Column(
      children: [
        LevelMeter(label: 'Microphone level', db: meters?.mic ?? -120),
        const SizedBox(height: 8),
        LevelMeter(label: 'Meeting source level', db: meters?.source ?? -120),
      ],
    );
  }
}

class LevelMeter extends StatelessWidget {
  const LevelMeter({super.key, required this.label, required this.db});

  final String label;
  final double db;

  @override
  Widget build(BuildContext context) {
    final fraction = ((db + 80) / 80).clamp(0.0, 1.0);
    final dbText = db <= -120 ? 'silent' : '${db.round()} dB';
    return Semantics(
      label: label,
      value: dbText,
      child: ExcludeSemantics(
        child: Row(
          children: [
            SizedBox(width: 150, child: Text(label)),
            Expanded(child: LinearProgressIndicator(value: fraction, minHeight: 10)),
            SizedBox(width: 64, child: Text(dbText, textAlign: TextAlign.end)),
          ],
        ),
      ),
    );
  }
}

class _Tones extends ConsumerWidget {
  const _Tones();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final headphones = ref.watch(setupProvider.select((s) => s.headphonesUid));
    final virtualUid = ref.watch(setupProvider.select((s) => s.virtualMic?.uid));
    final session = ref.read(sessionProvider.notifier);
    final bridge = ref.read(bridgeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: headphones == null ? null : () => session.guard('testTone', () => bridge.testTone(headphones)),
              icon: const Icon(Icons.headphones),
              label: const Text('Test headphones'),
            ),
            OutlinedButton.icon(
              onPressed: virtualUid == null ? null : () => session.guard('testTone', () => bridge.testTone(virtualUid)),
              icon: const Icon(Icons.mic_external_on),
              label: const Text('Test virtual mic'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text('Each test plays one quiet tone. Leave any call that uses BlackHole 2ch before testing.'),
      ],
    );
  }
}

class _Permission extends ConsumerWidget {
  const _Permission();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permission = ref.watch(setupProvider.select((s) => s.micPermission));
    final granted = permission == 'granted';
    return Row(
      children: [
        Icon(granted ? Icons.check_circle_outline : Icons.error_outline),
        const SizedBox(width: 8),
        Expanded(child: Text('Microphone permission: $permission')),
        if (!granted)
          FilledButton.tonal(
            onPressed: () => ref.read(setupProvider.notifier).refreshMicPermission(request: true),
            child: const Text('Request'),
          ),
      ],
    );
  }
}
