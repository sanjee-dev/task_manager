import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:task_manager/database/database_helper.dart';
import 'package:task_manager/models/task_model.dart';
import 'package:task_manager/services/task_api_service.dart';
import 'package:uuid/uuid.dart';

class TaskSyncService extends ChangeNotifier {
  TaskSyncService(this._database, this._api, {Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  static const _uuid = Uuid();
  static const _maxAttempts = 5;

  final DatabaseHelper _database;
  final TaskApiService _api;
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Future<void>? _syncFuture;
  bool _isSyncing = false;
  bool _started = false;
  bool _rerunRequested = false;
  bool _forceRetryRequested = false;
  String? _errorMessage;

  bool get isSyncing => _isSyncing;
  String? get errorMessage => _errorMessage;

  void start() {
    if (_started) return;
    _started = true;
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (results) {
        if (results.any((result) => result != ConnectivityResult.none)) {
          unawaited(synchronize());
        }
      },
      onError: (Object error) {
        _errorMessage = 'Could not monitor network connectivity: $error';
        notifyListeners();
      },
    );
    unawaited(_syncIfConnected());
  }

  Future<void> _syncIfConnected() async {
    try {
      final results = await _connectivity.checkConnectivity();
      if (results.any((result) => result != ConnectivityResult.none)) {
        await synchronize();
      }
    } catch (error) {
      _errorMessage = 'Could not check network connectivity: $error';
      notifyListeners();
    }
  }

  Future<void> synchronize({bool forceRetry = false}) {
    final running = _syncFuture;
    if (running != null) {
      _rerunRequested = true;
      _forceRetryRequested |= forceRetry;
      return running;
    }

    final future = _runSynchronization(forceRetry);
    _syncFuture = future;
    return future.whenComplete(() {
      _syncFuture = null;
      if (_rerunRequested) {
        _rerunRequested = false;
        final retry = _forceRetryRequested;
        _forceRetryRequested = false;
        unawaited(synchronize(forceRetry: retry));
      }
    });
  }

  Future<void> _runSynchronization(bool forceRetry) async {
    _isSyncing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _queueUntrackedTasks();
      final pendingOperations = await _database.getSyncOutbox();
      if (forceRetry) {
        for (final operation in pendingOperations) {
          await _database.updateSyncOperation(
            operation['mutation_id']! as String,
            attempts: 0,
            payload: operation['payload']! as String,
          );
        }
      }
      final operations = forceRetry
          ? pendingOperations
                .map((operation) => {...operation, 'attempts': 0})
                .toList()
          : pendingOperations;

      final blockedTasks = <String>{};
      for (final operation in operations) {
        final taskUuid = operation['task_uuid']! as String;
        if (blockedTasks.contains(taskUuid)) continue;
        await _pushOperation(operation);
        final task = await _database.getTaskByUuid(taskUuid);
        final syncStatus = TaskSyncStatus.fromValue(task?['sync_status']);
        if (syncStatus == TaskSyncStatus.failed ||
            syncStatus == TaskSyncStatus.conflict) {
          blockedTasks.add(taskUuid);
        }
      }

      await _pullChanges();
    } catch (error) {
      _errorMessage = 'Synchronization failed: $error';
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _queueUntrackedTasks() async {
    final records = await _database.getAllTaskRecords();
    final operations = await _database.getSyncOutbox();
    final queuedIds = operations.map((row) => row['task_uuid']).toSet();

    for (final record in records) {
      final syncStatus = TaskSyncStatus.fromValue(record['sync_status']);
      final taskUuid = record['task_uuid']?.toString();
      if (taskUuid == null ||
          queuedIds.contains(taskUuid) ||
          syncStatus == TaskSyncStatus.synced ||
          syncStatus == TaskSyncStatus.failed ||
          syncStatus == TaskSyncStatus.conflict) {
        continue;
      }
      final task = TaskModel.fromMap(record);
      final mutation = createMutation(
        task,
        task.isDeleted ? 'delete' : 'upsert',
      );
      await _database.enqueueSyncOperation(toOutboxRow(mutation));
      queuedIds.add(taskUuid);
    }
  }

  Future<void> _pushOperation(Map<String, Object?> operation) async {
    final mutationId = operation['mutation_id']! as String;
    final taskUuid = operation['task_uuid']! as String;
    var attempts = (operation['attempts'] as num).toInt();
    if (attempts >= _maxAttempts) {
      await _database.setTaskSyncState(
        taskUuid,
        status: 'failed',
        error: operation['last_error']?.toString(),
      );
      return;
    }

    var payload =
        jsonDecode(operation['payload']! as String) as Map<String, Object?>;
    final localTask = await _database.getTaskByUuid(taskUuid);
    if (localTask == null) {
      await _database.removeSyncOperation(mutationId);
      return;
    }

    if (attempts == 0) {
      final version = (localTask['server_version'] as num?)?.toInt() ?? 0;
      payload['base_version'] = version;
      await _database.updateSyncOperation(
        mutationId,
        attempts: attempts,
        payload: jsonEncode(payload),
        baseVersion: version,
      );
    }

    while (attempts < _maxAttempts) {
      attempts++;
      final encodedPayload = jsonEncode(payload);
      await _database.updateSyncOperation(
        mutationId,
        attempts: attempts,
        payload: encodedPayload,
      );

      try {
        final result = await _api.pushMutation(payload);
        final status = result['status'];
        if (status == 'synced') {
          await _acceptMutation(result, taskUuid, mutationId);
          await _database.removeSyncOperation(mutationId);
          return;
        }
        if (status == 'conflict') {
          await _recordConflict(result, taskUuid);
          await _database.removeTaskSyncOperations(taskUuid);
          return;
        }
        if (status == 'validation_error' ||
            status == 'idempotency_key_reused') {
          final error = jsonEncode(result['errors'] ?? result);
          _errorMessage = 'A task change could not be synchronized: $error';
          await _database.setTaskSyncState(
            taskUuid,
            status: 'failed',
            error: error,
          );
          await _database.removeTaskSyncOperations(taskUuid);
          return;
        }
        throw FormatException('Unexpected sync result: $status');
      } catch (error) {
        final retryable = _isRetryable(error);
        final message = error.toString();
        await _database.updateSyncOperation(
          mutationId,
          attempts: attempts,
          payload: encodedPayload,
          lastError: message,
        );
        if (!retryable || attempts >= _maxAttempts) {
          _errorMessage = 'A task change could not be synchronized: $message';
          await _database.setTaskSyncState(
            taskUuid,
            status: 'failed',
            error: message,
          );
          return;
        }
        await Future<void>.delayed(Duration(seconds: 1 << (attempts - 1)));
      }
    }
  }

  Future<void> _acceptMutation(
    Map<String, Object?> result,
    String taskUuid,
    String mutationId,
  ) async {
    final task = result['task'];
    if (task is Map<String, Object?>) {
      final remaining = (await _database.getSyncOutbox()).any(
        (operation) =>
            operation['task_uuid'] == taskUuid &&
            operation['mutation_id'] != mutationId,
      );
      if (remaining) {
        await _database.setTaskSyncState(
          taskUuid,
          status: 'pending',
          serverId: result['server_id']?.toString(),
          serverVersion: (result['version'] as num?)?.toInt(),
        );
      } else {
        await _database.applyRemoteTask(task, force: true);
      }
    } else {
      await _database.setTaskSyncState(
        taskUuid,
        status: 'synced',
        serverId: result['server_id']?.toString(),
        serverVersion: (result['version'] as num?)?.toInt() ?? 0,
      );
    }
  }

  Future<void> _recordConflict(
    Map<String, Object?> result,
    String taskUuid,
  ) async {
    final serverTask = result['task'];
    await _database.setTaskSyncState(
      taskUuid,
      status: 'conflict',
      error: 'The task changed on the server.',
      conflictData: serverTask == null ? null : jsonEncode(serverTask),
      serverId: result['server_id']?.toString(),
      serverVersion: (result['version'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> _pullChanges() async {
    final cursor = await _database.getSyncCursor();
    final response = await _api.getChanges(cursor);
    final data = response['data'];
    final meta = response['meta'];
    if (data is! List || meta is! Map<String, Object?>) {
      throw const FormatException('The task change response is incomplete.');
    }

    for (final item in data) {
      if (item is! Map<String, Object?>) {
        throw const FormatException(
          'The task change list contains invalid data.',
        );
      }
      await _database.applyRemoteTask(item);
    }

    final nextCursor = meta['next_cursor'];
    if (nextCursor is! num || nextCursor.toInt() < cursor) {
      throw const FormatException('The task change cursor is invalid.');
    }
    await _database.setSyncCursor(nextCursor.toInt());
  }

  Map<String, Object?> createMutation(TaskModel task, String operation) {
    final taskUuid = task.taskUuid;
    if (taskUuid == null) {
      throw StateError('A task must have a UUID before it can synchronize.');
    }
    final mutation = <String, Object?>{
      'mutation_id': _uuid.v4(),
      'task_uuid': taskUuid,
      'operation': operation,
      'base_version': task.serverVersion,
    };
    if (operation == 'upsert') {
      mutation['task'] = {
        'title': task.title,
        'note': task.note,
        'start_datetime': task.startDateTime.toUtc().toIso8601String(),
        'end_datetime': task.endDateTime.toUtc().toIso8601String(),
        'status': task.status.value,
      };
    }
    return mutation;
  }

  Map<String, Object?> toOutboxRow(Map<String, Object?> mutation) => {
    'mutation_id': mutation['mutation_id'],
    'task_uuid': mutation['task_uuid'],
    'operation': mutation['operation'],
    'payload': jsonEncode(mutation),
    'base_version': mutation['base_version'],
    'created_at': DateTime.now().toUtc().toIso8601String(),
    'attempts': 0,
    'last_error': null,
  };

  bool _isRetryable(Object error) {
    if (error is TaskApiException) return error.isRetryable;
    return error is TimeoutException ||
        error is SocketException ||
        error is http.ClientException;
  }

  @override
  void dispose() {
    unawaited(_connectivitySubscription?.cancel());
    _api.close();
    super.dispose();
  }
}
