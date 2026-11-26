import 'dart:async';

import 'package:livebridge/state/sample_player.dart';

/// Plays nothing. Records what was asked and lets a test end or fail the current sample.
class FakeSamplePlayer implements SamplePlayer {
  final _playing = StreamController<String?>.broadcast(sync: true);
  String? _current;

  /// Every address `play` was called with, in order.
  final List<String> played = [];

  /// How many times `stop` was called.
  int stops = 0;

  @override
  Stream<String?> get playing => _playing.stream;

  @override
  Future<void> play(String url) async {
    played.add(url);
    _current = url;
    _playing.add(url);
  }

  @override
  Future<void> stop() async {
    stops++;
    _idle();
  }

  /// The current sample played to its end.
  void finish() => _idle();

  /// The current sample could not be loaded or played.
  void fail() => _idle();

  @override
  void dispose() => _playing.close();

  void _idle() {
    if (_current == null) return;
    _current = null;
    _playing.add(null);
  }
}
