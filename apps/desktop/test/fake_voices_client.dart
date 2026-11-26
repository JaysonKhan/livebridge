import 'dart:async';

import 'package:livebridge/bridge/models.dart';
import 'package:livebridge/bridge/voices_client.dart';

/// Answers with a fixed list (or a failure) and remembers every request.
class FakeVoicesClient implements VoicesClient {
  FakeVoicesClient({List<Voice>? voices}) : voices = voices ?? defaultVoices();

  static const ariaEnglishSample = 'https://samples.example/aria-en.mp3';
  static const ariaSample = 'https://samples.example/aria.mp3';
  static const brunoSample = 'https://samples.example/bruno.mp3';

  /// The gateway's own fake voices; the first two can be listened to.
  static List<Voice> defaultVoices() => const [
    Voice(
      id: 'fakevoice0000000001',
      name: 'Fake Aria',
      gender: 'female',
      age: 'young',
      accent: 'american',
      language: 'en',
      useCase: 'conversational',
      description: 'Warm and clear',
      category: 'premade',
      previewUrl: ariaSample,
      previews: {'en': ariaEnglishSample},
    ),
    Voice(
      id: 'fakevoice0000000002',
      name: 'Fake Bruno',
      gender: 'male',
      age: 'middle_aged',
      accent: 'british',
      language: 'en',
      useCase: 'narration',
      description: 'A calm narrator',
      category: 'premade',
      previewUrl: brunoSample,
    ),
    Voice(
      id: 'fakevoice0000000003',
      name: 'Fake Dilnoza',
      gender: 'female',
      age: 'young',
      language: 'uz',
      useCase: 'conversational',
      category: 'premade',
    ),
    Voice(
      id: 'fakevoice0000000004',
      name: 'Fake Timur',
      gender: 'male',
      age: 'old',
      language: 'ru',
      useCase: 'news',
      category: 'premade',
    ),
  ];

  List<Voice> voices;

  /// Set to make the next requests fail.
  VoicesFailure? failure;

  /// Set to hold requests open until it completes.
  Completer<void>? gate;

  final List<({String url, String token})> calls = [];

  @override
  Future<List<Voice>> list({required String gatewayUrl, required String accessToken}) async {
    calls.add((url: gatewayUrl, token: accessToken));
    await gate?.future;
    if (failure != null) throw VoicesException(failure!);
    return voices;
  }
}
