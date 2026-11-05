import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/models/task_model.dart';

void main() {
  test('serializes task metadata and UTC date-times', () {
    final task = TaskModel(
      id: 7,
      taskUuid: '6cf199e6-9c58-4efb-81bd-45653057cd19',
      serverId: '6cf199e6-9c58-4efb-81bd-45653057cd19',
      title: 'Review API contract',
      note: 'Offline-safe',
      startDateTime: DateTime.utc(2026, 11, 5, 9),
      endDateTime: DateTime.utc(2026, 11, 5, 10),
      status: TaskStatus.done,
      createdAt: DateTime.utc(2026, 11, 4, 12),
      syncStatus: TaskSyncStatus.synced,
      serverVersion: 3,
      localUpdatedAt: DateTime.utc(2026, 11, 5, 8),
      syncError: null,
    );

    final restored = TaskModel.fromMap(task.toMap());

    expect(restored, task);
    expect(restored.startDateTime.isUtc, isTrue);
    expect(restored.endDateTime.isUtc, isTrue);
  });

  test('defaults unknown synchronization states to pending', () {
    expect(TaskSyncStatus.fromValue('unknown'), TaskSyncStatus.pending);
    expect(TaskSyncStatus.fromValue(null), TaskSyncStatus.pending);
  });
}
