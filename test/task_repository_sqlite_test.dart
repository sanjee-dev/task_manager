import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:task_manager/database/database_helper.dart';
import 'package:task_manager/models/task_model.dart';
import 'package:task_manager/repositories/task_repository.dart';
import 'package:task_manager/services/task_api_service.dart';
import 'package:task_manager/services/task_sync_service.dart';

void main() {
  late Directory directory;
  late DatabaseHelper database;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('task-manager-test-');
    database = DatabaseHelper.forTesting(
      '${directory.path}${Platform.pathSeparator}tasks.db',
    );
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test('upgrades the existing SQLite schema without losing tasks', () async {
    final oldDatabase = await databaseFactory.openDatabase(
      '${directory.path}${Platform.pathSeparator}tasks.db',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE tasks (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              note TEXT,
              start_datetime TEXT NOT NULL,
              end_datetime TEXT NOT NULL,
              status TEXT NOT NULL DEFAULT 'pending',
              created_at TEXT NOT NULL
            )
          ''');
          await db.insert('tasks', {
            'title': 'Existing task',
            'note': null,
            'start_datetime': '2026-11-05T09:00:00',
            'end_datetime': '2026-11-05T10:00:00',
            'status': 'pending',
            'created_at': '2026-11-04T12:00:00',
          });
        },
      ),
    );
    await oldDatabase.close();

    final records = await database.getAllTaskRecords();

    expect(records, hasLength(1));
    expect(records.single['title'], 'Existing task');
    expect(records.single['task_uuid'], isA<String>());
    expect(records.single['sync_status'], 'pending');
    expect(records.single['local_updated_at'], isA<String>());
    expect(await database.getSyncCursor(), 0);
    expect(await database.getSyncOutbox(), isEmpty);

    final sync = TaskSyncService(
      database,
      TaskApiService(
        client: MockClient((request) async {
          if (request.method == 'POST') {
            final body = jsonDecode(request.body) as Map<String, Object?>;
            final mutation =
                (body['mutations'] as List<Object?>).single
                    as Map<String, Object?>;
            final task = mutation['task'] as Map<String, Object?>;
            final serverTask = {
              ...task,
              'task_uuid': mutation['task_uuid'],
              'server_id': mutation['task_uuid'],
              'version': 1,
              'created_at': '2026-11-04T12:00:00.000000Z',
              'updated_at': '2026-11-05T12:00:00.000000Z',
              'deleted_at': null,
            };
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'mutation_id': mutation['mutation_id'],
                    'task_uuid': mutation['task_uuid'],
                    'server_id': mutation['task_uuid'],
                    'status': 'synced',
                    'version': 1,
                    'deleted': false,
                    'task': serverTask,
                  },
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'data': <Object?>[],
              'meta': {'next_cursor': 1},
            }),
            200,
          );
        }),
        baseUri: Uri.parse('https://example.test/api/v1/'),
      ),
    );
    await sync.synchronize();
    final syncedTask = (await database.getAllTaskRecords()).single;
    expect(syncedTask['sync_status'], 'synced');
    expect(syncedTask['server_id'], syncedTask['task_uuid']);
    expect(await database.getSyncOutbox(), isEmpty);
    expect(sync.errorMessage, isNull);
    sync.dispose();
  });

  test('persists offline creates and deletes with outbox mutations', () async {
    final sync = TaskSyncService(
      database,
      TaskApiService(
        client: MockClient((_) async => throw StateError('Unexpected request')),
        baseUri: Uri.parse('https://example.test/api/v1/'),
      ),
    );
    final repository = TaskRepository(database, sync);
    final start = DateTime.utc(2026, 11, 5, 9);
    final task = await repository.createTask(
      TaskModel(
        title: 'Offline task',
        startDateTime: start,
        endDateTime: start.add(const Duration(hours: 1)),
        createdAt: start,
      ),
    );

    expect(task.taskUuid, isNotNull);
    expect(await database.getSyncOutbox(), hasLength(1));
    expect((await repository.getTasks()).single.title, 'Offline task');

    await repository.deleteTask(task.id!);

    expect(await database.getAllTasks(), isEmpty);
    expect(
      (await database.getAllTaskRecords()).single['deleted_at'],
      isNotNull,
    );
    expect(await database.getSyncOutbox(), hasLength(2));

    await database.applyRemoteTask({
      'task_uuid': task.taskUuid,
      'server_id': task.taskUuid,
      'title': 'Remote copy',
      'note': null,
      'start_datetime': '2026-11-05T09:00:00.000Z',
      'end_datetime': '2026-11-05T10:00:00.000Z',
      'status': 'pending',
      'version': 1,
      'created_at': '2026-11-05T09:00:00.000Z',
      'updated_at': '2026-11-05T09:30:00.000Z',
      'deleted_at': null,
    });
    expect(await database.getAllTasks(), hasLength(1));
    expect((await database.getAllTasks()).single['sync_status'], 'conflict');
    sync.dispose();
  });

  test('keeps task rows and pending mutations isolated per account', () async {
    final sync = TaskSyncService(
      database,
      TaskApiService(
        client: MockClient((_) async => throw StateError('Unexpected request')),
        baseUri: Uri.parse('https://example.test/api/v1/'),
      ),
    );
    final repository = TaskRepository(database, sync);
    final start = DateTime.utc(2026, 11, 5, 9);
    final legacyTask = await repository.createTask(
      TaskModel(
        title: 'Existing offline task',
        startDateTime: start,
        endDateTime: start.add(const Duration(hours: 1)),
        createdAt: start,
      ),
    );

    await database.activateAccount('user-a');
    expect((await repository.getTasks()).single.id, legacyTask.id);
    await database.setSyncCursor(8);
    final taskA = await repository.createTask(
      TaskModel(
        title: 'User A task',
        startDateTime: start,
        endDateTime: start.add(const Duration(hours: 1)),
        createdAt: start,
      ),
    );
    expect(await database.getSyncOutbox(), hasLength(2));

    await database.activateAccount('user-b');
    expect(await repository.getTasks(), isEmpty);
    expect(await database.getSyncOutbox(), isEmpty);
    expect(await database.getSyncCursor(), 0);
    await database.setSyncCursor(2);
    await repository.createTask(
      TaskModel(
        title: 'User B task',
        startDateTime: start,
        endDateTime: start.add(const Duration(hours: 1)),
        createdAt: start,
      ),
    );
    expect(await repository.getTasks(), hasLength(1));
    expect(await database.getSyncOutbox(), hasLength(1));

    await database.activateAccount('user-a');
    expect(await database.getSyncCursor(), 8);
    expect((await repository.getTasks()).map((task) => task.title).toSet(), {
      'Existing offline task',
      'User A task',
    });
    expect(await database.getSyncOutbox(), hasLength(2));
    expect(await database.getTaskById(taskA.id!), isNotNull);
    sync.dispose();
  });

  test(
    'synchronizes queued edits in order using the latest server version',
    () async {
      final syncBases = <int>[];
      var serverVersion = 0;
      var serverTaskUuid = '';
      final sync = TaskSyncService(
        database,
        TaskApiService(
          client: MockClient((request) async {
            if (request.method == 'POST') {
              final body = jsonDecode(request.body) as Map<String, Object?>;
              final mutation =
                  (body['mutations'] as List<Object?>).single
                      as Map<String, Object?>;
              syncBases.add(mutation['base_version']! as int);
              serverVersion++;
              serverTaskUuid = mutation['task_uuid']! as String;
              final task = mutation['task'] as Map<String, Object?>;
              final serverTask = {
                ...task,
                'task_uuid': serverTaskUuid,
                'server_id': serverTaskUuid,
                'version': serverVersion,
                'created_at': '2026-11-05T09:00:00.000000Z',
                'updated_at': '2026-11-05T09:00:00.000000Z',
                'deleted_at': null,
              };
              return http.Response(
                jsonEncode({
                  'data': [
                    {
                      'mutation_id': mutation['mutation_id'],
                      'task_uuid': serverTaskUuid,
                      'server_id': serverTaskUuid,
                      'status': 'synced',
                      'version': serverVersion,
                      'task': serverTask,
                    },
                  ],
                }),
                200,
              );
            }
            return http.Response(
              jsonEncode({
                'data': <Object?>[],
                'meta': {'next_cursor': serverVersion},
              }),
              200,
            );
          }),
          baseUri: Uri.parse('https://example.test/api/v1/'),
        ),
      );
      final repository = TaskRepository(database, sync);
      final start = DateTime.utc(2026, 11, 5, 9);
      final created = await repository.createTask(
        TaskModel(
          title: 'Initial title',
          startDateTime: start,
          endDateTime: start.add(const Duration(hours: 1)),
          createdAt: start,
        ),
      );
      await repository.updateTask(created.copyWith(title: 'Edited title'));

      await sync.synchronize();

      expect(syncBases, [0, 1]);
      final savedTask = (await repository.getTasks()).single;
      expect(savedTask.title, 'Edited title');
      expect(savedTask.serverVersion, 2);
      expect(savedTask.syncStatus, TaskSyncStatus.synced);
      expect(await database.getSyncOutbox(), isEmpty);
      expect(sync.errorMessage, isNull);
      sync.dispose();
    },
  );

  test('retries a transient error with the same idempotent mutation', () async {
    var postCount = 0;
    String? originalBody;
    final sync = TaskSyncService(
      database,
      TaskApiService(
        client: MockClient((request) async {
          if (request.method == 'POST') {
            postCount++;
            if (postCount == 1) {
              originalBody = request.body;
              return http.Response('Temporarily unavailable', 503);
            }
            expect(request.body, originalBody);
            final body = jsonDecode(request.body) as Map<String, Object?>;
            final mutation =
                (body['mutations'] as List<Object?>).single
                    as Map<String, Object?>;
            final task = mutation['task'] as Map<String, Object?>;
            final taskUuid = mutation['task_uuid']! as String;
            final serverTask = {
              ...task,
              'task_uuid': taskUuid,
              'server_id': taskUuid,
              'version': 1,
              'created_at': '2026-11-05T09:00:00.000000Z',
              'updated_at': '2026-11-05T09:00:00.000000Z',
              'deleted_at': null,
            };
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'mutation_id': mutation['mutation_id'],
                    'task_uuid': taskUuid,
                    'server_id': taskUuid,
                    'status': 'synced',
                    'version': 1,
                    'task': serverTask,
                  },
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'data': <Object?>[],
              'meta': {'next_cursor': 1},
            }),
            200,
          );
        }),
        baseUri: Uri.parse('https://example.test/api/v1/'),
      ),
    );
    final repository = TaskRepository(database, sync);
    final start = DateTime.utc(2026, 11, 5, 9);
    await repository.createTask(
      TaskModel(
        title: 'Retry safely',
        startDateTime: start,
        endDateTime: start.add(const Duration(hours: 1)),
        createdAt: start,
      ),
    );

    await sync.synchronize();

    expect(postCount, 2);
    expect(
      (await repository.getTasks()).single.syncStatus,
      TaskSyncStatus.synced,
    );
    expect(await database.getSyncOutbox(), isEmpty);
    expect(sync.errorMessage, isNull);
    sync.dispose();
  });
}
