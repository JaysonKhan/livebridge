import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';

/// Why the voice list could not be read.
enum VoicesFailure {
  /// The gateway refused the access token.
  unauthorized,

  /// The gateway has no voice list (an older one).
  unsupported,

  /// The gateway answered, but has no list to give right now.
  unavailable,

  /// The gateway could not be reached.
  network,
}

class VoicesException implements Exception {
  const VoicesException(this.failure);

  final VoicesFailure failure;

  @override
  String toString() => 'VoicesException(${failure.name})';
}

/// Reads the voices a session may be spoken with.
abstract class VoicesClient {
  Future<List<Voice>> list({required String gatewayUrl, required String accessToken});
}

/// `GET <gateway>/v1/voices` with the access token — the same address and credential a session is created with.
class HttpVoicesClient implements VoicesClient {
  HttpVoicesClient({this.timeout = const Duration(seconds: 10)});

  /// For the whole exchange: connecting, the answer and its body.
  final Duration timeout;

  @override
  Future<List<Voice>> list({required String gatewayUrl, required String accessToken}) async {
    final uri = Uri.tryParse('${gatewayUrl.trim().replaceFirst(RegExp(r'/+$'), '')}/v1/voices');
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https')) || uri.host.isEmpty) {
      throw const VoicesException(VoicesFailure.network);
    }
    final client = HttpClient();
    final int status;
    final String body;
    try {
      (status, body) = await _get(client, uri, accessToken).timeout(timeout);
    } on Exception {
      // Refused, unreachable, a TLS failure, a broken answer or none in time: the gateway could not be reached.
      throw const VoicesException(VoicesFailure.network);
    } finally {
      client.close(force: true);
    }
    switch (status) {
      case HttpStatus.ok:
        break;
      case HttpStatus.unauthorized:
        throw const VoicesException(VoicesFailure.unauthorized);
      case HttpStatus.notFound:
        throw const VoicesException(VoicesFailure.unsupported);
      default:
        throw const VoicesException(VoicesFailure.unavailable);
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const VoicesException(VoicesFailure.unavailable);
    }
    final voices = decoded is Map ? decoded['voices'] : null;
    if (voices is! List) throw const VoicesException(VoicesFailure.unavailable);
    return voices.map(Voice.fromJson).nonNulls.toList();
  }

  static Future<(int, String)> _get(HttpClient client, Uri uri, String accessToken) async {
    final request = await client.getUrl(uri);
    // The token goes to the address that was typed and nowhere else.
    request.followRedirects = false;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
    final response = await request.close();
    return (response.statusCode, await const Utf8Decoder(allowMalformed: true).bind(response).join());
  }
}
