import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:task_manager/models/auth_user.dart';

class AuthApiException implements Exception {
  const AuthApiException(this.message, {required this.statusCode});

  final String message;
  final int statusCode;

  @override
  String toString() => message;
}

class AuthSession {
  const AuthSession({required this.token, required this.user});

  final String token;
  final AuthUser user;
}

class AuthApiService {
  AuthApiService({http.Client? client, Uri? baseUri})
    : _client = client ?? http.Client(),
      _baseUri = baseUri ?? _defaultApiRoot {
    if (kReleaseMode && _baseUri.scheme != 'https') {
      throw ArgumentError.value(
        _baseUri,
        'baseUri',
        'HTTPS is required for release builds.',
      );
    }
  }

  final http.Client _client;
  final Uri _baseUri;

  static Uri get _defaultApiRoot {
    final versionedBase = Uri.parse(
      const String.fromEnvironment(
        'TASK_API_BASE_URL',
        defaultValue: 'http://172.29.186.58:8000/api/v1/',
      ),
    );
    return versionedBase.resolve('../');
  }

  Future<void> register({required String name, required String email}) async {
    await _request('register', body: {'name': name, 'email': email});
  }

  Future<AuthSession> login(String username, String password) async {
    final response = await _request(
      'login',
      body: {'username': username, 'password': password},
    );
    final data = response['data'];
    if (data is! Map<String, Object?> ||
        data['token'] is! String ||
        data['user'] is! Map<String, Object?>) {
      throw const FormatException(
        'The login API returned an invalid response.',
      );
    }
    return AuthSession(
      token: data['token']! as String,
      user: AuthUser.fromJson(data['user']! as Map<String, Object?>),
    );
  }

  Future<AuthUser> getUser(String token) async {
    final response = await _request('user', token: token, method: 'GET');
    final data = response['data'];
    if (data is! Map<String, Object?>) {
      throw const FormatException(
        'The profile API returned an invalid response.',
      );
    }
    return AuthUser.fromJson(data);
  }

  Future<void> logout(String token) async {
    await _request('logout', token: token);
  }

  Future<void> forgotPassword(String email) async {
    await _request('forgot-password', body: {'email': email});
  }

  Future<void> resetPassword({
    required String email,
    required String token,
    required String password,
  }) async {
    await _request(
      'reset-password',
      body: {
        'email': email,
        'token': token,
        'password': password,
        'password_confirmation': password,
      },
    );
  }

  Future<void> changePassword({
    required String token,
    required String currentPassword,
    required String newPassword,
  }) async {
    await _request(
      'change-password',
      body: {
        'current_password': currentPassword,
        'password': newPassword,
        'password_confirmation': newPassword,
      },
      token: token,
    );
  }

  Future<Map<String, Object?>> _request(
    String endpoint, {
    Map<String, Object?>? body,
    String? token,
    String method = 'POST',
  }) async {
    final request = http.Request(method, _baseUri.resolve(endpoint))
      ..headers['accept'] = 'application/json';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    if (token != null) request.headers['authorization'] = 'Bearer $token';

    final streamedResponse = await _client
        .send(request)
        .timeout(const Duration(seconds: 20));
    final response = await http.Response.fromStream(streamedResponse);
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw FormatException(
        'The authentication API returned invalid JSON (HTTP ${response.statusCode}).',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const FormatException(
        'The authentication API response is invalid.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthApiException(
        decoded['message']?.toString() ?? 'Authentication failed.',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  void close() => _client.close();
}
