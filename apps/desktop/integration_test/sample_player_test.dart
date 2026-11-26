// The real sample player on a real device: the audio plugin, the network and the default output.
//
// Run (it plays a few seconds of speech out loud):
//   cd apps/desktop && flutter test integration_test/sample_player_test.dart -d macos \
//       --dart-define=LB_SAMPLE_URL=<a sample address from the gateway's GET /v1/voices>
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:livebridge/state/sample_player.dart';

const sampleUrl = String.fromEnvironment('LB_SAMPLE_URL');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a real sample plays to its end, can be replaced and stopped, and a broken address ends as idle', (
    tester,
  ) async {
    expect(sampleUrl, isNotEmpty, reason: 'pass --dart-define=LB_SAMPLE_URL=<sample address>');
    final player = AudioplayersSamplePlayer();
    addTearDown(player.dispose);
    final seen = <String?>[];
    player.playing.listen(seen.add);

    Future<void> until(bool Function() done, String what, {int seconds = 20}) async {
      for (var i = 0; i < seconds * 10; i++) {
        if (done()) return;
        await tester.pump(const Duration(milliseconds: 100));
      }
      fail('timed out waiting for $what; saw $seen');
    }

    // Plays to its end: the address, then idle, and it took as long as speech takes.
    final watch = Stopwatch()..start();
    await player.play(sampleUrl);
    await until(() => seen.length == 2, 'the sample to end', seconds: 60);
    expect(seen, [sampleUrl, null]);
    expect(watch.elapsed, greaterThan(const Duration(seconds: 1)));
    // ignore: avoid_print
    print('sample played for ${watch.elapsed.inMilliseconds} ms');

    // An address nothing answers on: no exception reaches the caller, and the player ends idle.
    seen.clear();
    await player.play('http://127.0.0.1:9/nothing.mp3');
    await until(() => seen.length == 2, 'the broken sample to end as idle', seconds: 45);
    expect(seen, ['http://127.0.0.1:9/nothing.mp3', null]);

    // A second sample replaces the first without passing through idle; stop ends it; the replaced one says nothing later.
    seen.clear();
    unawaited(player.play(sampleUrl));
    await tester.pump(const Duration(milliseconds: 700));
    unawaited(player.play(sampleUrl));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(seen, [sampleUrl, sampleUrl]);
    await player.stop();
    expect(seen, [sampleUrl, sampleUrl, null]);
    await tester.pump(const Duration(seconds: 2));
    expect(seen, [sampleUrl, sampleUrl, null]);
  });
}
