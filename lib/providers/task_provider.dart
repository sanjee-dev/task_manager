import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:task_manager/models/task_model.dart';
import 'package:task_manager/repositories/task_repository.dart';
import 'package:task_manager/services/task_sync_service.dart';

class TaskProvider extends ChangeNotifier {
  TaskProvider(this._repository, {this.syncService}) {
    syncService?.addListener(_onSyncServiceChanged);
    syncService?.start();
  }

  final TaskRepository _repository;
  final TaskSyncService? syncService;
  List<TaskModel> _tasks = [];
  bool _isLoading = false;
  String? _errorMessage;
  String _searchQuery = '';
  TaskStatus? _statusFilter;
  bool _wasSyncing = false;

  List<TaskModel> get tasks => List.unmodifiable(_tasks);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isSyncing => syncService?.isSyncing ?? false;
  String? get syncError => syncService?.errorMessage;
  String get searchQuery => _searchQuery;
  TaskStatus? get statusFilter => _statusFilter;
  int get totalCount => _tasks.length;
  int countFor(TaskStatus status) =>
      _tasks.where((task) => task.status == status).length;
  int get failedSyncCount =>
      _tasks.where((task) => task.syncStatus == TaskSyncStatus.failed).length;

  List<TaskModel> get visibleTasks {
    final query = _searchQuery.trim().toLowerCase();
    return _tasks.where((task) {
      final matchesStatus =
          _statusFilter == null || task.status == _statusFilter;
      final matchesQuery =
          query.isEmpty || task.title.toLowerCase().contains(query);
      return matchesStatus && matchesQuery;
    }).toList();
  }

  Future<void> loadTasks() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _tasks = await _repository.getTasks();
    } catch (error) {
      _errorMessage = 'Could not load tasks. $error';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setStatusFilter(TaskStatus? status) {
    _statusFilter = status;
    notifyListeners();
  }

  Future<void> addTask(TaskModel task) async {
    final savedTask = await _repository.createTask(task);
    _tasks = [..._tasks, savedTask]
      ..sort((a, b) => a.startDateTime.compareTo(b.startDateTime));
    notifyListeners();
    unawaited(syncService?.synchronize());
  }

  Future<void> updateTask(TaskModel task) async {
    await _repository.updateTask(task);
    final locallyUpdated = task.copyWith(
      localUpdatedAt: DateTime.now().toUtc(),
      syncStatus: TaskSyncStatus.pending,
      clearSyncError: true,
      clearConflictData: true,
    );
    _tasks =
        _tasks
            .map((current) => current.id == task.id ? locallyUpdated : current)
            .toList()
          ..sort((a, b) => a.startDateTime.compareTo(b.startDateTime));
    notifyListeners();
    unawaited(syncService?.synchronize());
  }

  Future<void> updateStatus(TaskModel task, TaskStatus status) =>
      updateTask(task.copyWith(status: status));

  Future<void> deleteTask(int id) async {
    await _repository.deleteTask(id);
    _tasks = _tasks.where((task) => task.id != id).toList();
    notifyListeners();
    unawaited(syncService?.synchronize());
  }

  Future<void> resolveConflict(
    String taskUuid, {
    required bool keepLocal,
  }) async {
    await _repository.resolveConflict(taskUuid, keepLocal: keepLocal);
    _tasks = await _repository.getTasks();
    notifyListeners();
    if (keepLocal) unawaited(syncService?.synchronize());
  }

  Future<void> retrySync() async {
    await syncService?.synchronize(forceRetry: true);
  }

  void _onSyncServiceChanged() {
    final syncing = syncService?.isSyncing ?? false;
    final completed = _wasSyncing && !syncing;
    _wasSyncing = syncing;
    notifyListeners();
    if (completed) unawaited(_reloadTasks());
  }

  Future<void> _reloadTasks() async {
    try {
      _tasks = await _repository.getTasks();
      notifyListeners();
    } catch (error) {
      _errorMessage = 'Could not refresh tasks after synchronization. $error';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    syncService?.removeListener(_onSyncServiceChanged);
    syncService?.dispose();
    super.dispose();
  }
}
