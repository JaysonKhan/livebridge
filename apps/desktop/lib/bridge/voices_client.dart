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

  /// The voice provider refused the ElevenLabs key the app sent (own-keys mode).
  invalidKey,
}

class VoicesException implements Exception {
  const VoicesException(this.failure);

  final VoicesFailure failure;

  @override
  String toString() => 'VoicesException(${failure.name})';
}

/// How the voice list is authorized, the same three ways as creating a session. Never printed.
sealed class VoicesAuth {
  const VoicesAuth();
}

/// `Authorization: Bearer <token>`: the own gateway's static token, or an account's access token.
class BearerAuth extends VoicesAuth {
  const BearerAuth(this.token);

  final String token;

  @override
  bool operator ==(Object other) => other is BearerAuth && other.token == token;

  @override
  int get hashCode => Object.hash(BearerAuth, token);

  @override
  String toString() => 'BearerAuth';
}

/// `X-ElevenLabs-Api-Key: <key>`: the voices of the user's own ElevenLabs account.
class ProviderKeyAuth extends VoicesAuth {
  const ProviderKeyAuth(this.elevenLabsKey);

  final String elevenLabsKey;

  @override
  bool operator ==(Object other) => other is ProviderKeyAuth && other.elevenLabsKey == elevenLabsKey;

  @override
  int get hashCode => Object.hash(ProviderKeyAuth, elevenLabsKey);

  @override
  String toString() => 'ProviderKeyAuth';
}

/// Reads the voices a session may be spoken with.
abstract class VoicesClient {
  Future<List<Voice>> list({required String gatewayUrl, required VoicesAuth auth});
}

/// `GET <gateway>/v1/voices` with the same credential a session is created with.
class HttpVoicesClient implements VoicesClient {
  HttpVoicesClient({this.timeout = const Duration(seconds: 10), this.onFailure});

  /// For the whole exchange: connecting, the answer and its body.
  final Duration timeout;

  /// Told of every failed listing — `v1/voices`, the HTTP status (null when there was no answer) and the error code;
  /// never a body or a credential. The diagnostic log listens.
  final void Function(String path, int? status, String code)? onFailure;

  static const _path = 'v1/voices';

  @override
  Future<List<Voice>> list({required String gatewayUrl, required VoicesAuth auth}) async {
    final uri = Uri.tryParse('${gatewayUrl.trim().replaceFirst(RegExp(r'/+$'), '')}/v1/voices');
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https')) || uri.host.isEmpty) {
      onFailure?.call(_path, null, 'bad_address');
      throw const VoicesException(VoicesFailure.network);
    }
    final client = HttpClient();
    final int status;
    final String body;
    try {
      (status, body) = await _get(client, uri, auth).timeout(timeout);
    } on Exception {
      // Refused, unreachable, a TLS failure, a broken answer or none in time: the gateway could not be reached.
      onFailure?.call(_path, null, 'network');
      throw const VoicesException(VoicesFailure.network);
    } finally {
      client.close(force: true);
    }
    if (status != HttpStatus.ok) onFailure?.call(_path, status, _errorCode(body) ?? 'error');
    switch (status) {
      case HttpStatus.ok:
        break;
      case HttpStatus.unauthorized:
        throw VoicesException(
          _errorCode(body) == 'invalid_key' ? VoicesFailure.invalidKey : VoicesFailure.unauthorized,
        );
      case HttpStatus.notFound:
        throw const VoicesException(VoicesFailure.unsupported);
      default:
        throw const VoicesException(VoicesFailure.unavailable);
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      onFailure?.call(_path, status, 'bad_body');
      throw const VoicesException(VoicesFailure.unavailable);
    }
    final voices = decoded is Map ? decoded['voices'] : null;
    if (voices is! List) {
      onFailure?.call(_path, status, 'bad_body');
      throw const VoicesException(VoicesFailure.unavailable);
    }
    return voices.map(Voice.fromJson).nonNulls.toList();
  }

  /// The `error` code of a JSON error body, or null.
  static String? _errorCode(String body) {
    try {
      final decoded = jsonDecode(body);
      final code = decoded is Map ? decoded['error'] : null;
      return code is String ? code : null;
    } on FormatException {
      return null;
    }
  }

  static Future<(int, String)> _get(HttpClient client, Uri uri, VoicesAuth auth) async {
    final request = await client.getUrl(uri);
    // The credential goes to the address that was typed and nowhere else.
    request.followRedirects = false;
    switch (auth) {
      case BearerAuth(:final token):
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      case ProviderKeyAuth(:final elevenLabsKey):
        request.headers.set('X-ElevenLabs-Api-Key', elevenLabsKey);
    }
    final response = await request.close();
    return (response.statusCode, await const Utf8Decoder(allowMalformed: true).bind(response).join());
  }
}
