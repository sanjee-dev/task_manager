import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class TaskApiException implements Exception {
  const TaskApiException(this.message, {required this.statusCode});

  final String message;
  final int statusCode;

  bool get isRetryable =>
      statusCode >= 500 || statusCode == 408 || statusCode == 429;

  @override
  String toString() => 'Task API error ($statusCode): $message';
}

class TaskApiService {
  TaskApiService({
    http.Client? client,
    Uri? baseUri,
    String? token,
    FutureOr<void> Function()? onUnauthorized,
  }) : this._internal(client, baseUri, token, onUnauthorized);

  TaskApiService._internal(
    http.Client? client,
    Uri? baseUri,
    this._token,
    this._onUnauthorized,
  ) : _client = client ?? http.Client(),
      _baseUri =
          baseUri ??
          Uri.parse(
            const String.fromEnvironment(
              'TASK_API_BASE_URL',
              defaultValue: 'http://172.29.186.58:8000/api/v1/',
            ),
          ) {
    if (kReleaseMode && _baseUri.scheme != 'https') {
      throw ArgumentError.value(
        _baseUri,
        'baseUri',
        'HTTPS is required for release builds.',
      );
    }
  }

  final http.Client _client;
  final String? _token;
  final FutureOr<void> Function()? _onUnauthorized;
  final Uri _baseUri;

  Future<Map<String, Object?>> pushMutation(
    Map<String, Object?> mutation,
  ) async {
    final response = await _client
        .post(
          _baseUri.resolve('sync'),
          headers: {
            'content-type': 'application/json',
            'accept': 'application/json',
            if (_token != null) 'authorization': 'Bearer $_token',
          },
          body: jsonEncode({
            'mutations': [mutation],
          }),
        )
        .timeout(const Duration(seconds: 20));
    final body = _decodeResponse(response);
    final data = body['data'];
    if (data is! List || data.isEmpty || data.first is! Map<String, Object?>) {
      throw const FormatException('The sync API returned an invalid response.');
    }
    return data.first as Map<String, Object?>;
  }

  Future<Map<String, Object?>> getChanges(int cursor) async {
    final uri = _baseUri
        .resolve('tasks')
        .replace(queryParameters: {'cursor': cursor.toString()});
    final response = await _client
        .get(
          uri,
          headers: {
            'accept': 'application/json',
            if (_token != null) 'authorization': 'Bearer $_token',
          },
        )
        .timeout(const Duration(seconds: 20));
    return _decodeResponse(response);
  }

  Map<String, Object?> _decodeResponse(http.Response response) {
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw TaskApiException(
          'The task API returned a non-JSON error response.',
          statusCode: response.statusCode,
        );
      }
      throw FormatException(
        'The task API returned invalid JSON (HTTP ${response.statusCode}).',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const FormatException(
        'The task API response must be a JSON object.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final onUnauthorized = _onUnauthorized;
      if (response.statusCode == 401 && onUnauthorized != null) {
        unawaited(Future<void>.sync(onUnauthorized));
      }
      final message = decoded['message']?.toString() ?? response.body;
      throw TaskApiException(message, statusCode: response.statusCode);
    }
    return decoded;
  }

  void close() => _client.close();
}
