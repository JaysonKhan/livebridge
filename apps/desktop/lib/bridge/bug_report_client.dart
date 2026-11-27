import 'dart:convert';
import 'dart:io';

/// The collector the app was built with; the native side reports the one in use (`telemetryStatus.endpoint`).
const String kDefaultCollector = 'https://jaysonkhan.com/api/services/v1';

/// A report was not accepted. [code] is `rate_limited`, `rejected` (the site refused the body) or `network`.
class BugReportException implements Exception {
  const BugReportException(this.code);

  final String code;

  @override
  String toString() => 'BugReportException($code)';
}

/// Sends a problem report (docs/telemetry-api.md, `POST bug-reports/`).
abstract class BugReportClient {
  Future<void> send(Uri endpoint, Map<String, Object?> body);
}

class HttpBugReportClient implements BugReportClient {
  HttpBugReportClient({this.timeout = const Duration(seconds: 20), this.onFailure});

  /// For the whole exchange: connecting, sending the log and the answer.
  final Duration timeout;

  /// Told of every failed send — `bug-reports/`, the HTTP status (null when there was no answer) and the error code;
  /// never the body. The diagnostic log listens.
  final void Function(String path, int? status, String code)? onFailure;

  static const _path = 'bug-reports/';

  @override
  Future<void> send(Uri endpoint, Map<String, Object?> body) async {
    final client = HttpClient();
    final int status;
    final String reply;
    try {
      (status, reply) = await _post(client, endpoint, body).timeout(timeout);
    } on Exception {
      onFailure?.call(_path, null, 'network');
      throw const BugReportException('network');
    } finally {
      client.close(force: true);
    }
    if (status == HttpStatus.created) return;
    onFailure?.call(_path, status, _errorCode(reply) ?? 'error');
    throw BugReportException(switch (status) {
      HttpStatus.tooManyRequests => 'rate_limited',
      HttpStatus.badRequest || HttpStatus.requestEntityTooLarge => 'rejected',
      _ => 'network',
    });
  }

  static Future<(int, String)> _post(HttpClient client, Uri endpoint, Map<String, Object?> body) async {
    final request = await client.postUrl(endpoint);
    request.followRedirects = false;
    request.headers.contentType = ContentType.json;
    request.add(utf8.encode(jsonEncode(body)));
    final response = await request.close();
    return (response.statusCode, await const Utf8Decoder(allowMalformed: true).bind(response).join());
  }

  static String? _errorCode(String body) {
    try {
      final decoded = jsonDecode(body);
      final code = decoded is Map ? decoded['error'] : null;
      return code is String ? code : null;
    } on FormatException {
      return null;
    }
  }
}
