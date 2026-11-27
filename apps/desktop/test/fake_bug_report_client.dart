import 'dart:async';

import 'package:livebridge/bridge/bug_report_client.dart';

/// Records every report and answers with what a test sets.
class FakeBugReportClient implements BugReportClient {
  final List<({Uri endpoint, Map<String, Object?> body})> sent = [];

  /// An error every send throws.
  Exception? error;

  /// While set and not completed, sends are recorded but do not finish.
  Completer<void>? gate;

  @override
  Future<void> send(Uri endpoint, Map<String, Object?> body) async {
    sent.add((endpoint: endpoint, body: body));
    final waiting = gate;
    if (waiting != null) await waiting.future;
    final failure = error;
    if (failure != null) throw failure;
  }
}
