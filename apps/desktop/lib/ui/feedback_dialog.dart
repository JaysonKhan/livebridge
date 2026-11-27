import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/labels.dart';
import '../state/connection_state.dart';
import '../state/providers.dart';
import 'adaptive/labeled_field.dart';
import 'theme/tokens.dart';

const feedbackMaxChars = 2000;

/// Returns true when the message was sent.
Future<bool> showFeedbackDialog(BuildContext context) async {
  final sent = await showDialog<bool>(context: context, builder: (_) => const _FeedbackDialog());
  return sent ?? false;
}

class _FeedbackDialog extends ConsumerStatefulWidget {
  const _FeedbackDialog();

  @override
  ConsumerState<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends ConsumerState<_FeedbackDialog> {
  final _message = TextEditingController();
  // Signed in with an account: its e-mail, which the person may change or remove.
  late final _email = TextEditingController(text: ref.read(connectionProvider).accountEmail ?? '');
  int? _rating;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    _email.dispose();
    super.dispose();
  }

  // Length in characters (code points), the unit the server counts.
  int get _length => _message.text.runes.length;
  bool get _emailOk => _email.text.trim().isEmpty || _email.text.contains('@');
  bool get _canSend => !_sending && _message.text.trim().isNotEmpty && _length <= feedbackMaxChars && _emailOk;

  Future<void> _send() async {
    final l = context.l10n;
    final email = _email.text.trim();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(bridgeProvider)
          .sendFeedback(message: _message.text.trim(), email: email.isEmpty ? null : email, rating: _rating);
      if (mounted) Navigator.of(context).pop(true);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e is PlatformException && e.code == 'rate_limited' ? l.feedbackRateLimited : l.feedbackFailed;
      });
    }
  }

  Widget _star(int value) {
    final filled = (_rating ?? 0) >= value;
    return Semantics(
      label: context.l10n.feedbackStar(value),
      button: true,
      selected: _rating == value,
      excludeSemantics: true,
      child: IconButton(
        key: Key('feedback-star-$value'),
        onPressed: _sending ? null : () => setState(() => _rating = _rating == value ? null : value),
        icon: Icon(filled ? Icons.star : Icons.star_border),
        color: filled ? context.tokens.caution.foreground : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final tooLong = _length > feedbackMaxChars;
    return AlertDialog(
      title: Text(l.feedbackButton),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.feedbackNote),
              const SizedBox(height: 12),
              LabeledField(
                label: l.feedbackMessageLabel,
                child: TextField(
                  key: const Key('feedback-message'),
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
                  key: const Key('feedback-email'),
                  controller: _email,
                  enabled: !_sending,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(errorText: _emailOk ? null : l.feedbackEmailInvalid),
                ),
              ),
              const SizedBox(height: 12),
              Text(l.feedbackRatingLabel, style: theme.textTheme.labelLarge),
              Row(children: [for (var i = 1; i <= 5; i++) _star(i)]),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  key: const Key('feedback-error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(onPressed: _sending ? null : () => Navigator.of(context).pop(false), child: Text(l.cancel)),
        FilledButton(key: const Key('feedback-send'), onPressed: _canSend ? _send : null, child: Text(l.feedbackSend)),
      ],
    );
  }
}
