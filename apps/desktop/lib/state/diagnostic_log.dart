import 'dart:collection';
import 'dart:convert';
import 'dart:io';

/// This run's lines kept in memory.
const int kDiagnosticMemoryLimit = 192 * 1024;

/// The log file is moved to `diagnostics.1.log` past this size, so at most about twice this stays on disk.
const int kDiagnosticFileLimit = 256 * 1024;

/// The most a problem report carries.
const int kDiagnosticReportLimit = 200 * 1024;

/// How much of the earlier runs (from the file) a report carries before this run.
const int _previousLimit = 64 * 1024;

/// One message's length, in characters.
const int _messageLimit = 400;

final List<(RegExp, String)> _secretPatterns = [
  (RegExp(r'Bearer\s+\S+', caseSensitive: false), 'Bearer [secret]'),
  (RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*'), '[secret]'),
  (RegExp(r'AIza[0-9A-Za-z_-]{20,}'), '[secret]'),
  (RegExp(r'sk_[0-9A-Za-z]{20,}'), '[secret]'),
  // Account tokens, provider keys and anything else token-shaped — a whole run of 32+ characters, except a UUID
  // (the install id is not a secret).
  (
    RegExp(
      r'(?<![A-Za-z0-9_-])'
      r'(?![0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}(?![A-Za-z0-9_-]))'
      r'[A-Za-z0-9_-]{32,}',
    ),
    '[secret]',
  ),
];

/// The C0 and C1 control characters (line breaks and tabs among them), DEL, and the Unicode line and paragraph
/// separators: a device name can carry any of them.
final RegExp _controlCharacters = RegExp(r'[\x00-\x1F\x7F-\x9F\u2028\u2029]+');

/// Makes [text] safe for the diagnostic log: each of the given [secrets] (6 characters or more), bearer tokens, JWTs,
/// provider keys and any token-shaped run of 32+ characters become `[secret]`; control characters (line breaks and
/// tabs among them) and the Unicode line and paragraph separators become spaces; the result is at most 400 characters
/// (then `…`).
String redact(String text, {Iterable<String> secrets = const []}) {
  var out = text;
  final known = secrets.where((s) => s.length >= 6).toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final secret in known) {
    out = out.replaceAll(secret, '[secret]');
  }
  for (final (pattern, replacement) in _secretPatterns) {
    out = out.replaceAll(pattern, replacement);
  }
  out = out.replaceAll(_controlCharacters, ' ').trim();
  final runes = out.runes;
  return runes.length > _messageLimit ? '${String.fromCharCodes(runes.take(_messageLimit))}…' : out;
}

/// The last at most [limit] bytes of [bytes], starting at a whole line, as text.
String _tail(List<int> bytes, int limit) {
  var start = 0;
  if (bytes.length > limit) {
    start = bytes.length - limit;
    // A newline byte never occurs inside a multi-byte character, so cutting after one keeps the text whole.
    final newline = bytes.indexOf(0x0A, start);
    start = newline < 0 ? bytes.length : newline + 1;
  }
  return const Utf8Decoder(allowMalformed: true).convert(bytes, start).trimRight();
}

String _two(int n) => n.toString().padLeft(2, '0');

String _date(DateTime t) => '${t.year}-${_two(t.month)}-${_two(t.day)}';

String _time(DateTime t) =>
    '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';

String _iso(DateTime t) {
  final offset = t.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final minutes = offset.inMinutes.abs();
  return '${_date(t)}T${_time(t)}$sign${_two(minutes ~/ 60)}:${_two(minutes % 60)}';
}

/// What happened in the app since it started, for a problem report: settings, devices, state changes, errors and
/// timings — never what was said, keys or tokens (every line goes through [redact]). This run is kept in memory;
/// with a folder, lines also go to a small rolling file so that a report after a restart still shows the run before.
class DiagnosticLog {
  /// A log with no file (tests, test runs, and when the folder cannot be written).
  DiagnosticLog.memory({DateTime Function()? now}) : this._(now ?? DateTime.now, null, null, 0, '');

  DiagnosticLog._(this._now, this._folder, this._file, this._fileBytes, this._previous) {
    final started = _now();
    _day = _date(started);
    _header = '=== LiveBridge run started ${_iso(started)}';
    _write(_header);
  }

  /// Opens the log in [folder] (created if missing), reading the end of the earlier runs first. A folder that cannot
  /// be written leaves a memory-only log.
  static Future<DiagnosticLog> open(Directory folder, {DateTime Function()? now}) async {
    var previous = '';
    RandomAccessFile? file;
    var size = 0;
    try {
      folder.createSync(recursive: true);
      final current = File(_path(folder, 'diagnostics.log'));
      final older = File(_path(folder, 'diagnostics.1.log'));
      previous = _tail([
        if (older.existsSync()) ...older.readAsBytesSync(),
        if (current.existsSync()) ...current.readAsBytesSync(),
      ], _previousLimit);
      if (current.existsSync() && current.lengthSync() >= kDiagnosticFileLimit) current.renameSync(older.path);
      file = current.openSync(mode: FileMode.append);
      size = file.lengthSync();
    } on FileSystemException {
      file = null;
    }
    return DiagnosticLog._(now ?? DateTime.now, folder, file, size, previous);
  }

  /// Where the log file goes: next to the analytics log. Null under ephemeral settings (automated runs) and on
  /// platforms the app does not support.
  static Directory? defaultFolder({Map<String, String>? environment, String? os}) {
    final env = environment ?? Platform.environment;
    if (env.containsKey('LIVEBRIDGE_EPHEMERAL_SETTINGS')) return null;
    switch (os ?? Platform.operatingSystem) {
      case 'macos':
        final home = env['HOME'];
        return home == null ? null : Directory('$home/Library/Application Support/LiveBridge');
      case 'windows':
        final appData = env['APPDATA'];
        return appData == null ? null : Directory('$appData\\LiveBridge');
    }
    return null;
  }

  static String _path(Directory folder, String name) => '${folder.path}${Platform.pathSeparator}$name';

  final DateTime Function() _now;
  final Directory? _folder;
  RandomAccessFile? _file;
  int _fileBytes;
  final String _previous;
  late final String _header;
  late String _day;
  final Queue<String> _lines = Queue();
  int _bytes = 0;
  int _dropped = 0;

  /// Values that must never appear in the log even if some message carries them (the own gateway's static token).
  Iterable<String> Function()? secrets;

  void add(String category, String message) {
    final t = _now();
    final day = _date(t);
    if (day != _day) {
      _day = day;
      _push('=== $day');
    }
    _push('${_time(t)} ${category.padRight(9)} ${redact(message, secrets: secrets?.call() ?? const [])}');
  }

  void _push(String line) {
    _lines.add(line);
    _bytes += utf8.encode(line).length + 1;
    while (_bytes > kDiagnosticMemoryLimit && _lines.length > 1) {
      _bytes -= utf8.encode(_lines.removeFirst()).length + 1;
      _dropped++;
    }
    _write(line);
  }

  void _write(String line) {
    final file = _file;
    if (file == null) return;
    try {
      final bytes = utf8.encode('$line\n');
      file.writeFromSync(bytes);
      _fileBytes += bytes.length;
      if (_fileBytes >= kDiagnosticFileLimit) _rotate(file);
    } on FileSystemException {
      _closeQuietly(file);
      _file = null;
    }
  }

  void _rotate(RandomAccessFile file) {
    final folder = _folder!;
    file.closeSync();
    File(_path(folder, 'diagnostics.log')).renameSync(_path(folder, 'diagnostics.1.log'));
    _file = File(_path(folder, 'diagnostics.log')).openSync(mode: FileMode.append);
    _fileBytes = 0;
  }

  static void _closeQuietly(RandomAccessFile file) {
    try {
      file.closeSync();
    } on FileSystemException {
      // Nothing more to lose.
    }
  }

  /// The text a report carries: the end of the earlier runs, then this run; at most [maxBytes] (UTF-8), dropping
  /// the oldest lines first.
  String text({int maxBytes = kDiagnosticReportLimit}) {
    final buffer = StringBuffer();
    if (_previous.isNotEmpty) buffer.writeln(_previous);
    buffer.writeln(_header);
    if (_dropped > 0) buffer.writeln('… $_dropped earlier lines dropped');
    _lines.forEach(buffer.writeln);
    final all = buffer.toString();
    final bytes = utf8.encode(all);
    return bytes.length <= maxBytes ? all : _tail(bytes, maxBytes);
  }

  Future<void> flush() async {
    try {
      _file?.flushSync();
    } on FileSystemException {
      // The next write notices.
    }
  }
}
