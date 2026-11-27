import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/bridge/bug_report_client.dart';

// Plain tests in their own file: a widget test in the same file would replace HttpClient with Flutter's mock.
void main() {
  group('HttpBugReportClient', () {
    late HttpServer server;
    late int status;
    late String reply;
    final requests = <({String method, String path, String? type, Object? body})>[];

    setUp(() async {
      status = 201;
      reply = '{"ok":true}';
      requests.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final text = await utf8.decoder.bind(request).join();
        requests.add((
          method: request.method,
          path: request.uri.path,
          type: request.headers.contentType?.mimeType,
          body: jsonDecode(text),
        ));
        request.response.statusCode = status;
        request.response.headers.contentType = ContentType.json;
        request.response.write(reply);
        await request.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    Uri endpoint() => Uri.parse('http://127.0.0.1:${server.port}/api/services/v1/bug-reports/');

    Future<String?> codeOf(Future<void> sending) async {
      try {
        await sending;
        return null;
      } on BugReportException catch (e) {
        return e.code;
      }
    }

    test('posts the report as JSON', () async {
      await HttpBugReportClient().send(endpoint(), {'app': 'livebridge', 'message': 'hi'});
      expect(requests.single.method, 'POST');
      expect(requests.single.path, '/api/services/v1/bug-reports/');
      expect(requests.single.type, 'application/json');
      expect(requests.single.body, {'app': 'livebridge', 'message': 'hi'});
    });

    test('maps the answers and reports failures with status and code only', () async {
      final failures = <(String, int?, String)>[];
      final client = HttpBugReportClient(
        timeout: const Duration(seconds: 2),
        onFailure: (path, status, code) => failures.add((path, status, code)),
      );
      final body = {'app': 'livebridge', 'message': 'hi', 'log': 'lbr_secretlogline'};
      status = 429;
      reply = '{"error":"rate_limited"}';
      expect(await codeOf(client.send(endpoint(), body)), 'rate_limited');
      status = 400;
      reply = '{"error":"bad_log"}';
      expect(await codeOf(client.send(endpoint(), body)), 'rejected');
      status = 413;
      reply = '{"error":"too_large"}';
      expect(await codeOf(client.send(endpoint(), body)), 'rejected');
      status = 500;
      reply = 'oops';
      expect(await codeOf(client.send(endpoint(), body)), 'network');
      final address = endpoint();
      await server.close(force: true);
      expect(await codeOf(client.send(address, body)), 'network');
      expect(failures, [
        ('bug-reports/', 429, 'rate_limited'),
        ('bug-reports/', 400, 'bad_log'),
        ('bug-reports/', 413, 'too_large'),
        ('bug-reports/', 500, 'error'),
        ('bug-reports/', null, 'network'),
      ]);
    });
  });
}
