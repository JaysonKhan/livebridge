import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livebridge/state/sample_player.dart';

import 'fake_sample_player.dart';

const _first = 'https://samples.example/first.mp3';
const _second = 'https://samples.example/second.mp3';

/// The audio plugin's player with nothing behind it: a test decides when a sample starts, ends or fails.
class _StubPlayer implements AudioPlayer {
  final _completes = StreamController<void>.broadcast(sync: true);
  final _started = Completer<void>();
  String? url;
  bool disposed = false;

  /// The sample loaded and is now audible.
  void start() => _started.complete();

  /// The sample could not be loaded (the plugin throws from `play`).
  void failToLoad([Object error = const FormatException('cannot decode')]) => _started.completeError(error);

  /// The sample played to its end.
  void finish() => _completes.add(null);

  /// The plugin reported an error while playing.
  void breakDown() => _completes.addError(StateError('playback failed'));

  @override
  Stream<void> get onPlayerComplete => _completes.stream;

  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) {
    url = (source as UrlSource).url;
    return _started.future;
  }

  @override
  Future<void> dispose() async => disposed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // What the widget tests rely on: the fake keeps the same contract as the real player below.
  group('FakeSamplePlayer', () {
    late FakeSamplePlayer player;
    late List<String?> seen;

    setUp(() {
      player = FakeSamplePlayer();
      seen = [];
      player.playing.listen(seen.add);
    });
    tearDown(() => player.dispose());

    test('play emits the address; a second play replaces it without passing through idle', () async {
      await player.play(_first);
      await player.play(_second);
      expect(seen, [_first, _second]);
      expect(player.played, [_first, _second]);
    });

    test('stop, the end of a sample and a failure each go back to idle; stop while idle says nothing', () async {
      await player.stop();
      expect(seen, isEmpty);
      await player.play(_first);
      await player.stop();
      await player.play(_first);
      player.finish();
      await player.play(_second);
      player.fail();
      expect(seen, [_first, null, _first, null, _second, null]);
      expect(player.stops, 2);
    });
  });

  group('AudioplayersSamplePlayer', () {
    late List<_StubPlayer> players;
    late AudioplayersSamplePlayer player;
    late List<String?> seen;

    setUp(() {
      players = [];
      player = AudioplayersSamplePlayer(
        newPlayer: () {
          players.add(_StubPlayer());
          return players.last;
        },
      );
      seen = [];
      player.playing.listen(seen.add);
    });
    tearDown(() => player.dispose());

    /// Lets stream events and continuations run.
    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('play starts that address and says so', () async {
      unawaited(player.play(_first));
      await settle();
      expect(players.single.url, _first);
      expect(seen, [_first]);
      players.single.start();
      await settle();
      expect(seen, [_first]);
    });

    test('a sample that plays to its end goes back to idle and its player is let go', () async {
      unawaited(player.play(_first));
      players.single.start();
      await settle();
      players.single.finish();
      await settle();
      expect(seen, [_first, null]);
      expect(players.single.disposed, isTrue);
    });

    test('a sample that cannot be loaded ends as idle and nothing is thrown at the caller', () async {
      final playing = player.play(_first);
      players.single.failToLoad();
      await playing;
      await settle();
      expect(seen, [_first, null]);
      expect(players.single.disposed, isTrue);
    });

    test('an error while playing ends as idle', () async {
      unawaited(player.play(_first));
      players.single.start();
      await settle();
      players.single.breakDown();
      await settle();
      expect(seen, [_first, null]);
    });

    test('a second sample replaces the first; whatever the first still reports is ignored', () async {
      final first = player.play(_first);
      await settle();
      unawaited(player.play(_second));
      await settle();
      expect(seen, [_first, _second]);
      expect(players.first.disposed, isTrue);
      expect(players.last.url, _second);

      // The replaced one was still loading: the plugin fails its `play` — with an Error, not an Exception — and may
      // still report an end. Neither reaches the caller or the state.
      players.first.failToLoad(StateError('disposed while loading'));
      players.first.finish();
      await first;
      await settle();
      expect(seen, [_first, _second]);
      expect(players.last.disposed, isFalse);
    });

    test('stop goes back to idle; stop while idle says nothing', () async {
      await player.stop();
      expect(seen, isEmpty);
      unawaited(player.play(_first));
      await settle();
      await player.stop();
      expect(seen, [_first, null]);
      expect(players.single.disposed, isTrue);
      // A late end of the stopped sample is not a second "idle".
      players.single.finish();
      await settle();
      expect(seen, [_first, null]);
    });
  });
}
