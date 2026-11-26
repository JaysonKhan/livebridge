import 'package:flutter_test/flutter_test.dart';

import 'fake_sample_player.dart';

// The contract every sample player keeps. It runs against the fake, which is what the widget tests rely on; the real
// player is exercised on a device by integration_test/sample_player_test.dart.
void main() {
  const first = 'https://samples.example/first.mp3';
  const second = 'https://samples.example/second.mp3';

  late FakeSamplePlayer player;
  late List<String?> seen;

  setUp(() {
    player = FakeSamplePlayer();
    seen = [];
    player.playing.listen(seen.add);
  });
  tearDown(() => player.dispose());

  test('play emits the address being played', () async {
    await player.play(first);
    expect(seen, [first]);
    expect(player.played, [first]);
  });

  test('a second play replaces the first without passing through idle', () async {
    await player.play(first);
    await player.play(second);
    expect(seen, [first, second]);
    expect(player.played, [first, second]);
  });

  test('stop goes back to idle', () async {
    await player.play(first);
    await player.stop();
    expect(seen, [first, null]);
    expect(player.stops, 1);
  });

  test('stop while idle says nothing', () async {
    await player.stop();
    expect(seen, isEmpty);
    expect(player.stops, 1);
  });

  test('a sample that ends goes back to idle', () async {
    await player.play(first);
    player.finish();
    expect(seen, [first, null]);
  });

  test('a sample that fails goes back to idle', () async {
    await player.play(first);
    player.fail();
    expect(seen, [first, null]);
  });

  test('after one sample ended another can be played', () async {
    await player.play(first);
    player.finish();
    await player.play(second);
    expect(seen, [first, null, second]);
  });
}
