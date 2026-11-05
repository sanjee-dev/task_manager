import 'dart:convert';

import 'package:task_manager/database/database_helper.dart';
import 'package:task_manager/models/task_model.dart';
import 'package:task_manager/services/task_sync_service.dart';
import 'package:uuid/uuid.dart';

class TaskRepository {
  TaskRepository(this._database, this._syncService);

  static const _uuid = Uuid();

  final DatabaseHelper _database;
  final TaskSyncService _syncService;

  Future<List<TaskModel>> getTasks() async {
    final rows = await _database.getAllTasks();
    return rows.map(TaskModel.fromMap).toList();
  }

  Future<TaskModel> createTask(TaskModel task) async {
    final now = DateTime.now().toUtc();
    final localTask = task.copyWith(
      taskUuid: task.taskUuid ?? _uuid.v4(),
      localUpdatedAt: now,
      syncStatus: TaskSyncStatus.pending,
      clearSyncError: true,
      clearConflictData: true,
    );
    final mutation = _syncService.createMutation(localTask, 'upsert');
    final id = await _database.insertTaskWithOutbox(
      localTask.toMap()..remove('id'),
      _syncService.toOutboxRow(mutation),
    );
    return localTask.copyWith(id: id);
  }

  Future<void> updateTask(TaskModel task) async {
    final id = task.id;
    if (id == null) throw ArgumentError('Cannot update a task without an id.');
    if (task.syncStatus == TaskSyncStatus.conflict) {
      throw StateError('Resolve the synchronization conflict before editing.');
    }
    final updatedTask = task.copyWith(
      taskUuid: task.taskUuid ?? _uuid.v4(),
      localUpdatedAt: DateTime.now().toUtc(),
      syncStatus: TaskSyncStatus.pending,
      clearSyncError: true,
      clearConflictData: true,
    );
    final mutation = _syncService.createMutation(updatedTask, 'upsert');
    await _database.updateTaskWithOutbox(
      id,
      updatedTask.toMap()..remove('id'),
      _syncService.toOutboxRow(mutation),
    );
  }

  Future<void> deleteTask(int id) async {
    final row = await _database.getTaskById(id);
    if (row == null) return;
    final taskUuid = row['task_uuid']?.toString() ?? _uuid.v4();
    final deletedAt = DateTime.now().toUtc();
    final task = TaskModel.fromMap(row).copyWith(
      taskUuid: taskUuid,
      deletedAt: deletedAt,
      localUpdatedAt: deletedAt,
      syncStatus: TaskSyncStatus.pending,
      clearSyncError: true,
      clearConflictData: true,
    );
    final mutation = _syncService.createMutation(task, 'delete');
    await _database.tombstoneTaskWithOutbox(
      id,
      taskUuid,
      deletedAt,
      _syncService.toOutboxRow(mutation),
    );
  }

  Future<void> resolveConflict(
    String taskUuid, {
    required bool keepLocal,
  }) async {
    final row = await _database.getTaskByUuid(taskUuid);
    if (row == null) return;
    final conflictData = row['conflict_data']?.toString();

    if (!keepLocal) {
      if (conflictData == null) {
        await _database.removeLocalTask(taskUuid);
      } else {
        final remote = jsonDecode(conflictData) as Map<String, Object?>;
        await _database.removeTaskSyncOperations(taskUuid);
        await _database.applyRemoteTask(remote, force: true);
      }
      return;
    }

    final task = TaskModel.fromMap(row).copyWith(
      syncStatus: TaskSyncStatus.pending,
      clearSyncError: true,
      clearConflictData: true,
      clearDeletedAt: row['deleted_at'] == null,
    );
    final mutation = _syncService.createMutation(
      task,
      task.isDeleted ? 'delete' : 'upsert',
    );
    await _database.resolveConflictWithLocal(
      taskUuid,
      task.toMap()..remove('id'),
      _syncService.toOutboxRow(mutation),
    );
  }
}
