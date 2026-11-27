import 'dart:convert';
import 'dart:ffi' show Abi;

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/bug_report_client.dart';
import '../bridge/models.dart';
import '../l10n/labels.dart';
import '../state/connection_state.dart';
import '../state/diagnostics.dart';
import '../state/providers.dart';
import '../state/setup_state.dart';
import 'adaptive/labeled_field.dart';
import 'feedback_dialog.dart' show feedbackMaxChars;

/// The bug icon in the window header (main screen and onboarding): opens "Report a problem" and confirms a sent
/// report.
class ReportProblemButton extends StatelessWidget {
  const ReportProblemButton({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return IconButton(
      key: const Key('report-problem'),
      tooltip: l.reportButton,
      icon: const Icon(Icons.bug_report_outlined),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        final thanks = l.reportSent;
        if (await showBugReportDialog(context)) messenger.showSnackBar(SnackBar(content: Text(thanks)));
      },
    );
  }
}

/// Returns true when the report was sent.
Future<bool> showBugReportDialog(BuildContext context) async =>
    await showDialog<bool>(context: context, builder: (_) => const _BugReportDialog()) ?? false;

/// What "Show what will be sent" shows: the device object, then the log, exactly as they are sent.
String bugReportPreview(Map<String, Object?> devices, String log) =>
    '${const JsonEncoder.withIndent('  ').convert(devices)}\n\n$log';

const _mono = TextStyle(
  fontFamily: 'Menlo',
  fontFamilyFallback: ['Consolas', 'Courier New', 'monospace'],
  fontSize: 12,
);

class _BugReportDialog extends ConsumerStatefulWidget {
  const _BugReportDialog();

  @override
  ConsumerState<_BugReportDialog> createState() => _BugReportDialogState();
}

class _BugReportDialogState extends ConsumerState<_BugReportDialog> {
  final _message = TextEditingController();
  // Signed in with an account: its e-mail, which the person may change or remove.
  late final _email = TextEditingController(text: ref.read(connectionProvider).accountEmail ?? '');
  bool _includeLog = true;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    _email.dispose();
    super.dispose();
  }

  // Length in characters (code points), the unit the site counts.
  int get _length => _message.text.runes.length;
  bool get _emailOk => _email.text.trim().isEmpty || _email.text.contains('@');
  bool get _canSend => !_sending && _message.text.trim().isNotEmpty && _length <= feedbackMaxChars && _emailOk;

  ({Map<String, Object?> devices, String log}) _attachment() =>
      (devices: describeDevices(ref.read(setupProvider)), log: ref.read(diagnosticLogProvider).text());

  Future<void> _preview() async {
    final l = context.l10n;
    final attachment = _attachment();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.reportPreviewTitle),
        content: SizedBox(
          width: 640,
          height: MediaQuery.sizeOf(ctx).height * 0.55,
          child: SingleChildScrollView(
            child: SelectableText(
              bugReportPreview(attachment.devices, attachment.log),
              key: const Key('report-preview-text'),
              style: _mono,
            ),
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l.close))],
      ),
    );
  }

  Future<void> _send() async {
    final l = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    setState(() {
      _sending = true;
      _error = null;
    });
    TelemetryStatus? status;
    try {
      status = await ref.read(bridgeProvider).telemetryStatus();
    } on Exception {
      status = null; // The report goes without versions, to the built-in address.
    }
    if (!mounted) return;
    final email = _email.text.trim();
    final attachment = _includeLog ? _attachment() : null;
    final installId = status != null && status.enabled ? status.installId : null;
    final body = <String, Object?>{
      'app': 'livebridge',
      if (installId != null && installId.isNotEmpty) 'install_id': installId,
      'message': _message.text.trim(),
      if (email.isNotEmpty) 'email': email,
      'app_version': ?status?.appVersion,
      'os_version': ?status?.osVersion,
      'platform': '${Abi.current()}',
      'ui_language': language,
      'connection_mode': ref.read(connectionProvider).mode?.name ?? 'none',
      if (attachment != null) ...{'devices': attachment.devices, 'log': attachment.log},
    };
    try {
      final configured = status?.endpoint.trim() ?? '';
      final base = (configured.isEmpty ? kDefaultCollector : configured).replaceFirst(RegExp(r'/+$'), '');
      await ref.read(bugReportClientProvider).send(Uri.parse('$base/bug-reports/'), body);
      if (mounted) Navigator.of(context).pop(true);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e is BugReportException && e.code == 'rate_limited' ? l.feedbackRateLimited : l.reportFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final tooLong = _length > feedbackMaxChars;
    return AlertDialog(
      title: Text(l.reportButton),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.reportNote),
              const SizedBox(height: 12),
              LabeledField(
                label: l.reportMessageLabel,
                child: TextField(
                  key: const Key('report-message'),
                  controller: _message,
                  enabled: !_sending,
                  minLines: 4,
                  maxLines: 8,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    counterText: '$_length/$feedbackMaxChars',
                    counterStyle: tooLong ? TextStyle(color: theme.colorScheme.error) : null,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              LabeledField(
                label: l.feedbackEmailLabel,
                child: TextField(
                  key: const Key('report-email'),
                  controller: _email,
                  enabled: !_sending,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(errorText: _emailOk ? null : l.feedbackEmailInvalid),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                key: const Key('report-include-log'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _includeLog,
                onChanged: _sending ? null : (v) => setState(() => _includeLog = v ?? false),
                title: Text(l.reportIncludeLog),
                subtitle: Text(l.reportIncludeLogNote),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const Key('report-preview'),
                  onPressed: _includeLog ? _preview : null,
                  icon: const Icon(Icons.visibility_outlined),
                  label: Text(l.reportShowLog),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  key: const Key('report-error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(onPressed: _sending ? null : () => Navigator.of(context).pop(false), child: Text(l.cancel)),
        FilledButton(key: const Key('report-send'), onPressed: _canSend ? _send : null, child: Text(l.feedbackSend)),
      ],
    );
  }
}
