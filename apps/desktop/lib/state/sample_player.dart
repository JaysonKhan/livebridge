import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Plays a voice's sample from its address, one at a time.
abstract class SamplePlayer {
  /// The address being played, null when idle. Emits null when a sample ends or fails.
  Stream<String?> get playing;

  /// Stops whatever is playing first.
  Future<void> play(String url);

  Future<void> stop();

  void dispose();
}

/// Samples through the `audioplayers` plugin, on the system's default output. Each sample gets a player of its own,
/// so nothing a replaced sample still reports can be mistaken for the current one.
class AudioplayersSamplePlayer implements SamplePlayer {
  /// [newPlayer] makes the plugin's player for one sample; tests pass a stand-in.
  AudioplayersSamplePlayer({this._newPlayer = AudioPlayer.new});

  final AudioPlayer Function() _newPlayer;
  final _playing = StreamController<String?>.broadcast();
  AudioPlayer? _player;

  @override
  Stream<String?> get playing => _playing.stream;

  @override
  Future<void> play(String url) async {
    _release();
    final player = _newPlayer();
    _player = player;
    // An error on the plugin's event stream ends the sample like its last second does.
    player.onPlayerComplete.listen((_) => _ended(player), onError: (Object _) => _ended(player));
    _playing.add(url);
    try {
      await player.play(UrlSource(url));
    } on Object {
      // Could not be loaded or played — or was replaced while loading, which the plugin reports as an error too.
      // Either way the caller only ever sees "idle".
      _ended(player);
    }
  }

  @override
  Future<void> stop() async {
    if (_player == null) return;
    _release();
    _playing.add(null);
  }

  @override
  void dispose() {
    _release();
    _playing.close();
  }

  void _ended(AudioPlayer player) {
    if (!identical(player, _player)) return;
    _release();
    _playing.add(null);
  }

  void _release() {
    final player = _player;
    _player = null;
    if (player != null) unawaited(player.dispose().catchError((Object _) {}));
  }
}

/// The app's one sample player. Tests override this with a fake.
final samplePlayerProvider = Provider<SamplePlayer>((ref) {
  final player = AudioplayersSamplePlayer();
  ref.onDispose(player.dispose);
  return player;
});
