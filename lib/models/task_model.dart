enum TaskStatus {
  pending('pending', 'Pending'),
  done('done', 'Done');

  const TaskStatus(this.value, this.label);

  final String value;
  final String label;

  static TaskStatus fromValue(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return TaskStatus.pending;
    }

    for (final status in TaskStatus.values) {
      if (status.value == normalized ||
          status.label.toLowerCase() == normalized) {
        return status;
      }
    }

    return TaskStatus.pending;
  }
}

enum TaskSyncStatus {
  pending,
  synced,
  failed,
  conflict;

  static TaskSyncStatus fromValue(Object? value) {
    for (final status in values) {
      if (status.name == value?.toString()) return status;
    }
    return TaskSyncStatus.pending;
  }
}

class TaskModel {
  const TaskModel({
    this.id,
    this.taskUuid,
    this.serverId,
    required this.title,
    this.note,
    required this.startDateTime,
    required this.endDateTime,
    this.status = TaskStatus.pending,
    required this.createdAt,
    this.syncStatus = TaskSyncStatus.pending,
    this.serverVersion = 0,
    this.localUpdatedAt,
    this.deletedAt,
    this.syncError,
    this.conflictData,
  });

  final int? id;
  final String? taskUuid;
  final String? serverId;
  final String title;
  final String? note;
  final DateTime startDateTime;
  final DateTime endDateTime;
  final TaskStatus status;
  final DateTime createdAt;
  final TaskSyncStatus syncStatus;
  final int serverVersion;
  final DateTime? localUpdatedAt;
  final DateTime? deletedAt;
  final String? syncError;
  final String? conflictData;

  bool get isDeleted => deletedAt != null;

  TaskModel copyWith({
    int? id,
    String? taskUuid,
    String? serverId,
    String? title,
    String? note,
    DateTime? startDateTime,
    DateTime? endDateTime,
    TaskStatus? status,
    DateTime? createdAt,
    TaskSyncStatus? syncStatus,
    int? serverVersion,
    DateTime? localUpdatedAt,
    DateTime? deletedAt,
    bool clearNote = false,
    bool clearServerId = false,
    bool clearDeletedAt = false,
    bool clearSyncError = false,
    String? syncError,
    bool clearConflictData = false,
    String? conflictData,
  }) {
    return TaskModel(
      id: id ?? this.id,
      taskUuid: taskUuid ?? this.taskUuid,
      serverId: clearServerId ? null : serverId ?? this.serverId,
      title: title ?? this.title,
      note: clearNote ? null : note ?? this.note,
      startDateTime: startDateTime ?? this.startDateTime,
      endDateTime: endDateTime ?? this.endDateTime,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      syncStatus: syncStatus ?? this.syncStatus,
      serverVersion: serverVersion ?? this.serverVersion,
      localUpdatedAt: localUpdatedAt ?? this.localUpdatedAt,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
      syncError: clearSyncError ? null : syncError ?? this.syncError,
      conflictData: clearConflictData
          ? null
          : conflictData ?? this.conflictData,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'task_uuid': taskUuid,
    'server_id': serverId,
    'title': title,
    'note': note,
    'start_datetime': startDateTime.toUtc().toIso8601String(),
    'end_datetime': endDateTime.toUtc().toIso8601String(),
    'status': status.value,
    'created_at': createdAt.toUtc().toIso8601String(),
    'sync_status': syncStatus.name,
    'server_version': serverVersion,
    'local_updated_at': localUpdatedAt?.toUtc().toIso8601String(),
    'deleted_at': deletedAt?.toUtc().toIso8601String(),
    'sync_error': syncError,
    'conflict_data': conflictData,
  };

  factory TaskModel.fromMap(Map<String, Object?> map) => TaskModel(
    id: map['id'] as int?,
    taskUuid: map['task_uuid']?.toString(),
    serverId: map['server_id']?.toString(),
    title: map['title']?.toString() ?? '',
    note: map['note']?.toString(),
    startDateTime: DateTime.parse(map['start_datetime']?.toString() ?? '')
        .toUtc(),
    endDateTime: DateTime.parse(map['end_datetime']?.toString() ?? '').toUtc(),
    status: TaskStatus.fromValue(map['status']),
    createdAt: DateTime.parse(map['created_at']?.toString() ?? '').toUtc(),
    syncStatus: TaskSyncStatus.fromValue(map['sync_status']),
    serverVersion: (map['server_version'] as num?)?.toInt() ?? 0,
    localUpdatedAt: map['local_updated_at'] == null
        ? null
        : DateTime.parse(map['local_updated_at'].toString()).toUtc(),
    deletedAt: map['deleted_at'] == null
        ? null
        : DateTime.parse(map['deleted_at'].toString()).toUtc(),
    syncError: map['sync_error']?.toString(),
    conflictData: map['conflict_data']?.toString(),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          taskUuid == other.taskUuid &&
          serverId == other.serverId &&
          title == other.title &&
          note == other.note &&
          startDateTime == other.startDateTime &&
          endDateTime == other.endDateTime &&
          status == other.status &&
          createdAt == other.createdAt &&
          syncStatus == other.syncStatus &&
          serverVersion == other.serverVersion &&
          localUpdatedAt == other.localUpdatedAt &&
          deletedAt == other.deletedAt &&
          syncError == other.syncError &&
          conflictData == other.conflictData;

  @override
  int get hashCode => Object.hash(
    id,
    taskUuid,
    serverId,
    title,
    note,
    startDateTime,
    endDateTime,
    status,
    createdAt,
    syncStatus,
    serverVersion,
    localUpdatedAt,
    deletedAt,
    syncError,
    conflictData,
  );
}
