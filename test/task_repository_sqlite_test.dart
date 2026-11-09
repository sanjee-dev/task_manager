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
          await db.rawUpdate(
            "UPDATE sqlite_sequence SET seq = 9 WHERE name = 'tasks'",
          );
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
    final nextId = await (await database.database).insert('tasks', {
      'task_uuid': '12121212-1212-4121-8121-121212121212',
      'title': 'After migration',
      'start_datetime': '2026-11-05T09:00:00',
      'end_datetime': '2026-11-05T10:00:00',
      'created_at': '2026-11-05T08:00:00',
      'local_updated_at': '2026-11-05T08:00:00',
    });
    expect(nextId, 10);
    await (await database.database).delete(
      'tasks',
      where: 'id = ?',
      whereArgs: [nextId],
    );

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

  test(
    'upgrades account-partitioned rows and retains pending outbox changes',
    () async {
      final oldDatabase = await databaseFactory.openDatabase(
        '${directory.path}${Platform.pathSeparator}tasks.db',
        options: OpenDatabaseOptions(
          version: 4,
          onCreate: (db, version) async {
            await db.execute('''
            CREATE TABLE tasks (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              task_uuid TEXT NOT NULL UNIQUE,
              server_id TEXT,
              title TEXT NOT NULL,
              note TEXT,
              start_datetime TEXT NOT NULL,
              end_datetime TEXT NOT NULL,
              status TEXT NOT NULL DEFAULT 'pending',
              created_at TEXT NOT NULL,
              sync_status TEXT NOT NULL DEFAULT 'pending',
              server_version INTEGER NOT NULL DEFAULT 0,
              local_updated_at TEXT NOT NULL,
              deleted_at TEXT,
              sync_error TEXT,
              conflict_data TEXT,
              account_id TEXT NOT NULL DEFAULT 'legacy'
            )
          ''');
            await db.execute(
              'CREATE INDEX tasks_account_start ON tasks(account_id, start_datetime)',
            );
            await db.execute('''
            CREATE TABLE sync_outbox (
              mutation_id TEXT PRIMARY KEY,
              task_uuid TEXT NOT NULL,
              operation TEXT NOT NULL CHECK (operation IN ('upsert', 'delete')),
              payload TEXT NOT NULL,
              base_version INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL,
              attempts INTEGER NOT NULL DEFAULT 0,
              last_error TEXT,
              account_id TEXT NOT NULL DEFAULT 'legacy'
            )
          ''');
            await db.execute('''
            CREATE TABLE sync_state (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
            await db.insert('sync_state', {
              'key': 'cursor:user-a',
              'value': '8',
            });
            await db.insert('sync_state', {
              'key': 'cursor:user-b',
              'value': '16',
            });
            await db.insert('tasks', {
              'task_uuid': '34343434-3434-4434-8434-343434343434',
              'title': 'Pending account task',
              'start_datetime': '2026-11-05T09:00:00Z',
              'end_datetime': '2026-11-05T10:00:00Z',
              'created_at': '2026-11-05T08:00:00Z',
              'sync_status': 'pending',
              'server_version': 0,
              'local_updated_at': '2026-11-05T08:00:00Z',
              'account_id': 'user-a',
            });
            await db.insert('sync_outbox', {
              'mutation_id': '45454545-4545-4454-8454-454545454545',
              'task_uuid': '34343434-3434-4434-8434-343434343434',
              'operation': 'upsert',
              'payload': '{}',
              'base_version': 0,
              'created_at': '2026-11-05T08:00:00Z',
              'account_id': 'user-a',
            });
            await db.rawUpdate(
              "UPDATE sqlite_sequence SET seq = 20 WHERE name = 'tasks'",
            );
          },
        ),
      );
      await oldDatabase.close();

      await database.activateAccount('user-a');
      expect(await database.getSyncCursor(), 0);
      expect(
        (await database.getAllTaskRecords()).single['title'],
        'Pending account task',
      );
      expect(await database.getSyncOutbox(), hasLength(1));

      await database.activateAccount('user-b');
      expect(await database.getSyncCursor(), 0);
      await database.applyRemoteTask({
        'task_uuid': '34343434-3434-4434-8434-343434343434',
        'server_id': '34343434-3434-4434-8434-343434343434',
        'title': 'Shared task copy',
        'note': null,
        'start_datetime': '2026-11-05T09:00:00Z',
        'end_datetime': '2026-11-05T10:00:00Z',
        'status': 'pending',
        'version': 1,
        'created_at': '2026-11-05T08:00:00Z',
        'updated_at': '2026-11-05T08:30:00Z',
        'deleted_at': null,
      });
      expect(
        (await database.getAllTaskRecords()).single['title'],
        'Shared task copy',
      );
      expect(await database.getSyncOutbox(), isEmpty);

      await database.activateAccount('user-a');
      expect(
        (await database.getAllTaskRecords()).single['sync_status'],
        'pending',
      );
      expect(await database.getSyncOutbox(), hasLength(1));
    },
  );

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

  test(
    'keeps pending mutations account-bound while caching shared tasks',
    () async {
      final sync = TaskSyncService(
        database,
        TaskApiService(
          client: MockClient(
            (_) async => throw StateError('Unexpected request'),
          ),
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
      final taskB = await repository.createTask(
        TaskModel(
          title: 'User B task',
          startDateTime: start,
          endDateTime: start.add(const Duration(hours: 1)),
          createdAt: start,
        ),
      );
      await database.applyRemoteTask({
        'task_uuid': taskA.taskUuid,
        'server_id': taskA.taskUuid,
        'title': 'User A task',
        'note': null,
        'start_datetime': start.toIso8601String(),
        'end_datetime': start.add(const Duration(hours: 1)).toIso8601String(),
        'status': 'pending',
        'version': 1,
        'created_at': start.toIso8601String(),
        'updated_at': start.toIso8601String(),
        'deleted_at': null,
      });
      expect(await repository.getTasks(), hasLength(2));
      expect((await repository.getTasks()).map((task) => task.title).toSet(), {
        'User A task',
        'User B task',
      });
      expect(await database.getSyncOutbox(), hasLength(1));
      expect(await database.getTaskById(taskB.id!), isNotNull);

      await database.activateAccount('user-a');
      expect(await database.getSyncCursor(), 8);
      expect((await repository.getTasks()).map((task) => task.title).toSet(), {
        'Existing offline task',
        'User A task',
      });
      expect(await database.getSyncOutbox(), hasLength(2));
      expect(await database.getTaskById(taskA.id!), isNotNull);
      sync.dispose();
    },
  );

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
