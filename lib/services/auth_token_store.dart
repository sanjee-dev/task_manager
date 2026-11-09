import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:task_manager/models/auth_user.dart';

class StoredSession {
  const StoredSession({required this.token, required this.user});

  final String token;
  final AuthUser user;
}

abstract class AuthTokenStore {
  Future<StoredSession?> readSession();
  Future<void> writeSession(String token, AuthUser user);
  Future<void> clear();
}

class SecureAuthTokenStore implements AuthTokenStore {
  SecureAuthTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _sessionKey = 'task_manager.auth_session';
  final FlutterSecureStorage _storage;

  @override
  Future<StoredSession?> readSession() async {
    final value = await _storage.read(key: _sessionKey);
    if (value == null) return null;
    final json = jsonDecode(value);
    if (json is! Map<String, Object?> ||
        json['token'] is! String ||
        json['user'] is! Map<String, Object?>) {
      await clear();
      throw const FormatException('The saved sign-in session is invalid.');
    }
    return StoredSession(
      token: json['token']! as String,
      user: AuthUser.fromJson(json['user']! as Map<String, Object?>),
    );
  }

  @override
  Future<void> writeSession(String token, AuthUser user) => _storage.write(
    key: _sessionKey,
    value: jsonEncode({'token': token, 'user': user.toJson()}),
  );

  @override
  Future<void> clear() => _storage.delete(key: _sessionKey);
}
