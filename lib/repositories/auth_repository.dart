import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:task_manager/models/auth_user.dart';
import 'package:task_manager/services/auth_api_service.dart';
import 'package:task_manager/services/auth_token_store.dart';

class AuthRepository {
  AuthRepository(this._api, this._tokenStore);

  final AuthApiService _api;
  final AuthTokenStore _tokenStore;

  Future<StoredSession?> readSession() => _tokenStore.readSession();

  Future<StoredSession?> restoreSession() async {
    final stored = await _tokenStore.readSession();
    if (stored == null) return null;
    try {
      final user = await _api.getUser(stored.token);
      await _tokenStore.writeSession(stored.token, user);
      return StoredSession(token: stored.token, user: user);
    } on AuthApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        await _tokenStore.clear();
        return null;
      }
      if (error.statusCode >= 500) return stored;
      rethrow;
    } on TimeoutException {
      return stored;
    } on SocketException {
      return stored;
    } on http.ClientException {
      return stored;
    }
  }

  Future<AuthUser> login(String email, String password) async {
    final session = await _api.login(email, password);
    await _tokenStore.writeSession(session.token, session.user);
    return session.user;
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) => _api.register(name: name, email: email, password: password);

  Future<void> verifyEmailOtp({required String email, required String otp}) =>
      _api.verifyEmailOtp(email: email, otp: otp);

  Future<void> resendOtp(String email) => _api.resendOtp(email);

  Future<void> forgotPassword(String email) => _api.forgotPassword(email);

  Future<String> verifyResetOtp({required String email, required String otp}) =>
      _api.verifyResetOtp(email: email, otp: otp);

  Future<void> resetPassword({
    required String email,
    required String resetToken,
    required String password,
  }) => _api.resetPassword(
    email: email,
    resetToken: resetToken,
    password: password,
  );

  Future<void> changePassword({
    required String token,
    required String currentPassword,
    required String newPassword,
  }) => _api.changePassword(
    token: token,
    currentPassword: currentPassword,
    newPassword: newPassword,
  );

  Future<void> logout(String token) => _api.logout(token);

  Future<void> clearSession() => _tokenStore.clear();

  void close() => _api.close();
}
