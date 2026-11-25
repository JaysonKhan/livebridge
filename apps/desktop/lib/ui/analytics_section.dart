import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/models.dart';
import '../l10n/labels.dart';
import '../state/analytics_state.dart';
import '../state/session_state.dart';
import '../state/time_format.dart';

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _formatIso(String? iso) {
  final t = iso == null ? null : DateTime.tryParse(iso);
  return t == null ? '—' : formatDateTime(t.toLocal());
}

/// Collapsible "Analytics" card: the numbers-only log, with its switch, timing table and log actions.
class AnalyticsSection extends ConsumerStatefulWidget {
  const AnalyticsSection({super.key});

  @override
  ConsumerState<AnalyticsSection> createState() => _AnalyticsSectionState();
}

class _AnalyticsSectionState extends ConsumerState<AnalyticsSection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // Reload once a session has ended, if the owner is looking at the section.
    ref.listen(sessionProvider.select((s) => s.running), (was, now) {
      if (was == true && !now && _open) ref.read(analyticsProvider.notifier).refresh();
    });
    return ExpansionTile(
      leading: const Icon(Icons.insights),
      title: Text(l.analyticsTitle),
      subtitle: Text(l.analyticsSubtitle),
      onExpansionChanged: (open) {
        _open = open;
        if (open) ref.read(analyticsProvider.notifier).refresh();
      },
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: const [_AnalyticsBody()],
    );
  }
}

class _AnalyticsBody extends ConsumerWidget {
  const _AnalyticsBody();

  Future<void> _exportLog(BuildContext context, WidgetRef ref) async {
    final path = await ref.read(analyticsProvider.notifier).exportLog();
    if (path == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.exportSaved(path))));
  }

  Future<void> _clearLog(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.analyticsClearTitle),
        content: Text(l.analyticsClearBody),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(l.delete)),
        ],
      ),
    );
    if (ok == true) await ref.read(analyticsProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final state = ref.watch(analyticsProvider);
    final notifier = ref.read(analyticsProvider.notifier);
    final s = state.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.analyticsPrivacy),
        SwitchListTile(
          key: const Key('analytics-switch'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(l.analyticsEnabled),
          value: state.enabled,
          onChanged: notifier.setEnabled,
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: state.loading ? null : notifier.refresh,
              icon: const Icon(Icons.refresh),
              label: Text(l.refresh),
            ),
            OutlinedButton.icon(
              onPressed: () => _exportLog(context, ref),
              icon: const Icon(Icons.download),
              label: Text(l.analyticsExportLog),
            ),
            OutlinedButton.icon(
              onPressed: () => _clearLog(context, ref),
              icon: const Icon(Icons.delete_outline),
              label: Text(l.analyticsClearLog),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (s == null)
          if (state.loading) const LinearProgressIndicator() else const SizedBox.shrink()
        else ...[
          Text(l.analyticsSessions(s.sessions)),
          Text(l.analyticsTurns(s.turns)),
          Text(l.analyticsFirst(_formatIso(s.firstAt))),
          Text(l.analyticsLast(_formatIso(s.lastAt))),
          const SizedBox(height: 12),
          _TimingTable(summary: s),
          const SizedBox(height: 12),
          Text(l.analyticsErrorsTitle, style: Theme.of(context).textTheme.labelLarge),
          if (s.errors.isEmpty)
            Text(l.analyticsNoErrors)
          else
            for (final e in s.errors.entries) Text('${e.key}: ${e.value}'),
          const SizedBox(height: 12),
          Text(l.analyticsReconnects(s.reconnects)),
          Text(l.analyticsEmptyTurns(s.emptyTurns)),
          Text(l.analyticsRatedGood(s.ratedGood)),
          Text(l.analyticsRatedBad(s.ratedBad)),
          Text(l.analyticsFileSize(_formatBytes(s.fileSizeBytes))),
          SelectableText(l.analyticsPath(s.path)),
        ],
      ],
    );
  }
}

/// Timing rows, only for the stats that have data.
class _TimingTable extends StatelessWidget {
  const _TimingTable({required this.summary});

  final AnalyticsSummary summary;

  Widget _cell(BuildContext context, String text, {bool header = false, bool numeric = true}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
    child: Text(
      text,
      textAlign: numeric ? TextAlign.end : TextAlign.start,
      style: header ? Theme.of(context).textTheme.labelMedium : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final rows = <(String, TimingStat?)>[
      (l.analyticsRowE2e, summary.e2eMs),
      (l.analyticsRowStt, summary.sttCommitMs),
      (l.analyticsRowTranslateFirst, summary.translateFirstMs),
      (l.analyticsRowTranslateTotal, summary.translateTotalMs),
      (l.analyticsRowTtsFirst, summary.ttsFirstAudioMs),
    ].where((r) => r.$2 != null).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    return Table(
      columnWidths: const {0: FlexColumnWidth(2.4)},
      children: [
        TableRow(
          children: [
            _cell(context, l.analyticsTimingTitle, header: true, numeric: false),
            _cell(context, l.analyticsColCount, header: true),
            _cell(context, l.analyticsColP50, header: true),
            _cell(context, l.analyticsColP95, header: true),
            _cell(context, l.analyticsColMax, header: true),
          ],
        ),
        for (final (label, stat) in rows)
          TableRow(
            children: [
              _cell(context, label, numeric: false),
              _cell(context, '${stat!.count}'),
              _cell(context, '${stat.p50}'),
              _cell(context, '${stat.p95}'),
              _cell(context, '${stat.max}'),
            ],
          ),
      ],
    );
  }
}
