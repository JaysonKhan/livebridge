import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/state/diagnostic_log.dart';

/// Realistic shapes of the secrets the app holds (none of them real).
const elevenLabsKey = 'sk_3f9a1c0b7d2e4f6a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e';
const geminiKey = 'AIzaSyD3x-AmPlE_kEy0123456789abcdefghijk';
const refreshToken = 'q7Zr0-vN3kP_x9LmT2bW8yC4dF6hJ1sA5eG0iK3oU7w';
const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.c2lnbmF0dXJlLXZhbHVl';

void main() {
  late Directory temp;
  var clock = DateTime(2026, 11, 27, 10, 0, 0);
  DateTime now() => clock;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('lb-diag-');
    clock = DateTime(2026, 11, 27, 10, 0, 0);
  });
  tearDown(() => temp.deleteSync(recursive: true));

  group('redact', () {
    test('redacts keys, tokens and given secrets', () {
      final out = redact(
        'keys $elevenLabsKey $geminiKey refresh=$refreshToken Authorization: Bearer abc.def jwt $jwt '
        'static dev-token-1 end',
        secrets: ['dev-token-1'],
      );
      for (final secret in [elevenLabsKey, geminiKey, refreshToken, 'abc.def', jwt, 'dev-token-1']) {
        expect(out, isNot(contains(secret)), reason: secret);
      }
      expect(out, contains('[secret]'));
      expect(out, endsWith('end'));
      expect(redact('t 3f2b6c1e-9d0a-4c1b-8f6e-2a7d5b9c0e11ABCDEFGH u'), 't [secret] u');
    });

    test('keeps what is useful', () {
      const text =
          'install 3f2b6c1e-9d0a-4c1b-8f6e-2a7d5b9c0e11 model gemini-3.5-flash-lite '
          'at package:livebridge/state/connection_state.dart:123';
      expect(redact(text), text);
    });

    test('short secrets are not used for matching', () {
      expect(redact('state ready', secrets: ['', 'a', 'ready']), 'state ready');
    });

    test('one line per entry, capped', () {
      final out = redact('line one\nline two\ttab "quoted" 🎧\r\n');
      expect(out, 'line one line two tab "quoted" 🎧');
      expect(redact('${'x' * 20} ${'y ' * 400}').runes.length, lessThanOrEqualTo(401));
    });
  });

  group('DiagnosticLog', () {
    test('lines carry the time and category and stay one line', () {
      final log = DiagnosticLog.memory(now: now);
      clock = DateTime(2026, 11, 27, 10, 0, 1, 250);
      log.add('devices', 'mic "AirPods\nPro" 🎧');
      final lines = log.text().split('\n');
      expect(lines.first, startsWith('=== LiveBridge run started 2026-11-27T10:00:00.000'));
      expect(lines, contains('10:00:01.250 devices   mic "AirPods Pro" 🎧'));
    });

    test('given secrets are redacted by value', () {
      final log = DiagnosticLog.memory(now: now)..secrets = () => ['my-static-token'];
      log.add('error', 'refused my-static-token');
      expect(log.text(), isNot(contains('my-static-token')));
    });

    test('a new day gets a date line', () {
      final log = DiagnosticLog.memory(now: now);
      clock = DateTime(2026, 11, 28, 0, 0, 5);
      log.add('state', 'ready');
      expect(log.text(), contains('=== 2026-11-28'));
    });

    test('memory cap drops the oldest lines with a marker', () {
      final log = DiagnosticLog.memory(now: now);
      for (var i = 0; i < 3000; i++) {
        log.add('turn', 'out #$i ${'pad ' * 20}');
      }
      final text = log.text(maxBytes: 1 << 30);
      expect(utf8.encode(text).length, lessThanOrEqualTo(kDiagnosticMemoryLimit + 1024));
      expect(text, startsWith('=== LiveBridge run started'));
      expect(text, contains('earlier lines dropped'));
      expect(text.trimRight(), endsWith('out #2999 ${'pad ' * 20}'.trimRight()));
    });

    test('report text is capped and keeps the newest line', () {
      final log = DiagnosticLog.memory(now: now);
      for (var i = 0; i < 100; i++) {
        log.add('turn', 'out #$i ${'é' * 40}');
      }
      final text = log.text(maxBytes: 1000);
      expect(utf8.encode(text).length, lessThanOrEqualTo(1000));
      expect(text.trimRight(), endsWith('out #99 ${'é' * 40}'));
    });

    test('file rotates past its limit and the next run sees the earlier run', () async {
      final first = await DiagnosticLog.open(temp, now: now);
      for (var i = 0; i < 3000; i++) {
        first.add('turn', 'first-run #$i ${'fill ' * 18}');
      }
      await first.flush();
      expect(File('${temp.path}/diagnostics.1.log').existsSync(), isTrue);
      expect(File('${temp.path}/diagnostics.log').lengthSync(), lessThan(kDiagnosticFileLimit));

      clock = DateTime(2026, 11, 27, 11, 0, 0);
      final second = await DiagnosticLog.open(temp, now: now);
      second.add('state', 'second-run');
      final text = second.text();
      expect(text, contains('first-run #2999'));
      expect(text.indexOf('first-run #2999'), lessThan(text.indexOf('=== LiveBridge run started 2026-11-27T11:00')));
      expect(text.trimRight(), endsWith('second-run'));
      expect(utf8.encode(text).length, lessThanOrEqualTo(kDiagnosticReportLimit));
    });

    test('unwritable folder: the log still works in memory', () async {
      final blocker = File('${temp.path}/not-a-folder')..writeAsStringSync('x');
      final log = await DiagnosticLog.open(Directory('${blocker.path}/sub'), now: now);
      log.add('state', 'ready');
      await log.flush();
      expect(log.text(), contains('state     ready'));
    });

    test('default folder follows the analytics log and is off for test runs', () {
      expect(
        DiagnosticLog.defaultFolder(environment: {'HOME': '/Users/a'}, os: 'macos')?.path,
        '/Users/a/Library/Application Support/LiveBridge',
      );
      expect(
        DiagnosticLog.defaultFolder(environment: {'APPDATA': r'C:\Users\a\AppData\Roaming'}, os: 'windows')?.path,
        r'C:\Users\a\AppData\Roaming\LiveBridge',
      );
      expect(
        DiagnosticLog.defaultFolder(
          environment: {'HOME': '/Users/a', 'LIVEBRIDGE_EPHEMERAL_SETTINGS': '1'},
          os: 'macos',
        ),
        isNull,
      );
      expect(DiagnosticLog.defaultFolder(environment: {'HOME': '/home/a'}, os: 'linux'), isNull);
    });
  });
}
