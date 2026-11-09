import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:task_manager/database/database_helper.dart';
import 'package:task_manager/models/auth_user.dart';
import 'package:task_manager/providers/task_provider.dart';
import 'package:task_manager/repositories/auth_repository.dart';
import 'package:task_manager/services/auth_api_service.dart';
import 'package:task_manager/services/task_api_service.dart';
import 'package:task_manager/services/task_sync_service.dart';
import 'package:task_manager/repositories/task_repository.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider(this._repository, this._database);

  final AuthRepository _repository;
  final DatabaseHelper _database;
  AuthUser? _user;
  TaskProvider? _taskProvider;
  bool _isLoading = true;
  bool _handlingUnauthorized = false;
  String? _startupError;

  AuthUser? get user => _user;
  TaskProvider? get taskProvider => _taskProvider;
  bool get isLoading => _isLoading;
  String? get startupError => _startupError;

  Future<void> initialize() async {
    try {
      final session = await _repository.restoreSession();
      if (session != null) {
        await _activateSession(session.token, session.user);
      }
    } on SocketException catch (error) {
      _startupError = 'Could not verify the saved sign-in session: $error';
    } on TimeoutException catch (error) {
      _startupError = 'Could not verify the saved sign-in session: $error';
    } on Exception catch (error) {
      _startupError = 'Could not restore the saved sign-in session: $error';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> login(String email, String password) async {
    final user = await _repository.login(email, password);
    final session = await _repository.readSession();
    if (session == null) {
      throw StateError('The sign-in session was not saved.');
    }
    await _activateSession(session.token, user);
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) => _repository.register(name: name, email: email, password: password);

  Future<void> verifyEmailOtp({required String email, required String otp}) =>
      _repository.verifyEmailOtp(email: email, otp: otp);

  Future<void> resendOtp(String email) => _repository.resendOtp(email);

  Future<void> forgotPassword(String email) =>
      _repository.forgotPassword(email);

  Future<String> verifyResetOtp({required String email, required String otp}) =>
      _repository.verifyResetOtp(email: email, otp: otp);

  Future<void> resetPassword({
    required String email,
    required String resetToken,
    required String password,
  }) => _repository.resetPassword(
    email: email,
    resetToken: resetToken,
    password: password,
  );

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final session = await _repository.readSession();
    if (session == null) throw StateError('You are not signed in.');
    try {
      await _repository.changePassword(
        token: session.token,
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
    } on AuthApiException catch (error) {
      if (error.statusCode == 401) await _handleUnauthorized();
      rethrow;
    }
  }

  Future<void> logout() async {
    Object? requestError;
    try {
      await _taskProvider?.stopSync();
      final session = await _repository.readSession();
      if (session != null) await _repository.logout(session.token);
    } on Exception catch (error) {
      requestError = error;
    } finally {
      try {
        await _clearActiveSession();
      } finally {
        await _repository.clearSession();
      }
    }
    if (requestError != null) throw requestError;
  }

  Future<void> _activateSession(String token, AuthUser user) async {
    if (_user != null) await _clearActiveSession();
    await _database.activateAccount(user.id.toString());
    final syncService = TaskSyncService(
      _database,
      TaskApiService(token: token, onUnauthorized: _handleUnauthorized),
    );
    final taskProvider = TaskProvider(
      TaskRepository(_database, syncService),
      syncService: syncService,
    );
    _user = user;
    _taskProvider = taskProvider;
    _startupError = null;
    notifyListeners();
    await taskProvider.loadTasks();
  }

  Future<void> _handleUnauthorized() async {
    if (_handlingUnauthorized || _user == null) return;
    _handlingUnauthorized = true;
    try {
      try {
        await _clearActiveSession();
      } finally {
        await _repository.clearSession();
      }
    } finally {
      _handlingUnauthorized = false;
    }
  }

  Future<void> _clearActiveSession() async {
    final taskProvider = _taskProvider;
    _taskProvider = null;
    try {
      await taskProvider?.stopSync();
    } finally {
      taskProvider?.dispose();
      _database.deactivateAccount();
      _user = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    final taskProvider = _taskProvider;
    if (taskProvider != null) {
      unawaited(_shutdownTaskProvider(taskProvider));
    }
    _repository.close();
    super.dispose();
  }

  Future<void> _shutdownTaskProvider(TaskProvider provider) async {
    await provider.stopSync();
    provider.dispose();
  }
}
