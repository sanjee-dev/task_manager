import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class DatabaseHelper {
  DatabaseHelper._() : _databasePath = null;

  DatabaseHelper.forTesting(this._databasePath);

  static final DatabaseHelper instance = DatabaseHelper._();
  static const _databaseName = 'task_manager.db';
  static const _databaseVersion = 5;
  final String? _databasePath;
  Database? _database;
  String _activeAccountId = 'legacy';

  Future<Database> get database async {
    if (_database != null) return _database!;
    final path =
        _databasePath ??
        (kIsWeb
            ? _databaseName
            : join(await getDatabasesPath(), _databaseName));
    _database = await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: (db, version) async {
        await _createTasksTable(db);
        await _createSyncOutboxTable(db);
        await _createSyncStateTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE tasks ADD COLUMN task_uuid TEXT');
          await db.execute('ALTER TABLE tasks ADD COLUMN server_id TEXT');
          await db.execute(
            "ALTER TABLE tasks ADD COLUMN sync_status TEXT NOT NULL DEFAULT 'pending'",
          );
          await db.execute(
            'ALTER TABLE tasks ADD COLUMN server_version INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE tasks ADD COLUMN local_updated_at TEXT',
          );
          await db.execute('ALTER TABLE tasks ADD COLUMN deleted_at TEXT');
          await db.execute('ALTER TABLE tasks ADD COLUMN sync_error TEXT');

          final rows = await db.query('tasks', columns: ['id', 'created_at']);
          const uuid = Uuid();
          for (final row in rows) {
            await db.update(
              'tasks',
              {
                'task_uuid': uuid.v4(),
                'local_updated_at': _asUtcIsoString(row['created_at']),
              },
              where: 'id = ?',
              whereArgs: [row['id']],
            );
          }
          await db.execute(
            'CREATE UNIQUE INDEX tasks_task_uuid_unique ON tasks(task_uuid)',
          );
          await _createSyncOutboxTable(db);
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE tasks ADD COLUMN conflict_data TEXT');
          await _createSyncStateTable(db);
        }
        if (oldVersion < 4) {
          await db.execute(
            "ALTER TABLE tasks ADD COLUMN account_id TEXT NOT NULL DEFAULT 'legacy'",
          );
          if (oldVersion >= 2) {
            await db.execute(
              "ALTER TABLE sync_outbox ADD COLUMN account_id TEXT NOT NULL DEFAULT 'legacy'",
            );
          }
          await db.execute(
            'CREATE INDEX tasks_account_start ON tasks(account_id, start_datetime)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS sync_outbox_account_created ON sync_outbox(account_id, created_at)',
          );
        }
        if (oldVersion < 5) {
          final previousSequenceRows = await db.rawQuery(
            'SELECT seq FROM sqlite_sequence WHERE name = ?',
            ['tasks'],
          );
          final previousSequence = previousSequenceRows.isEmpty
              ? 0
              : (previousSequenceRows.single['seq'] as num).toInt();
          await db.execute('''
            CREATE TABLE tasks_v5 (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              task_uuid TEXT NOT NULL,
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
              account_id TEXT NOT NULL DEFAULT 'legacy',
              UNIQUE (task_uuid, account_id)
            )
          ''');
          await db.execute('''
            INSERT INTO tasks_v5 (
              id, task_uuid, server_id, title, note, start_datetime,
              end_datetime, status, created_at, sync_status, server_version,
              local_updated_at, deleted_at, sync_error, conflict_data, account_id
            )
            SELECT
              id, task_uuid, server_id, title, note, start_datetime,
              end_datetime, status, created_at, sync_status, server_version,
              local_updated_at, deleted_at, sync_error, conflict_data, account_id
            FROM tasks
          ''');
          await db.execute('DROP TABLE tasks');
          await db.execute('ALTER TABLE tasks_v5 RENAME TO tasks');
          await db.execute(
            'CREATE INDEX tasks_account_start ON tasks(account_id, start_datetime)',
          );
          final currentSequenceRows = await db.rawQuery(
            'SELECT seq FROM sqlite_sequence WHERE name = ?',
            ['tasks'],
          );
          final currentSequence = currentSequenceRows.isEmpty
              ? 0
              : (currentSequenceRows.single['seq'] as num).toInt();
          if (previousSequence > currentSequence) {
            if (currentSequenceRows.isEmpty) {
              await db.insert('sqlite_sequence', {
                'name': 'tasks',
                'seq': previousSequence,
              });
            } else {
              await db.rawUpdate(
                'UPDATE sqlite_sequence SET seq = ? WHERE name = ?',
                [previousSequence, 'tasks'],
              );
            }
          }
          await db.update(
            'sync_state',
            {'value': '0'},
            where: 'key = ? OR key LIKE ?',
            whereArgs: ['cursor', 'cursor:%'],
          );
        }
      },
    );
    return _database!;
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  Future<void> activateAccount(String accountId) async {
    if (accountId.isEmpty || accountId == 'legacy') {
      throw ArgumentError.value(accountId, 'accountId', 'Invalid account ID.');
    }
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.update(
        'tasks',
        {'account_id': accountId},
        where: 'account_id = ?',
        whereArgs: ['legacy'],
      );
      await transaction.update(
        'sync_outbox',
        {'account_id': accountId},
        where: 'account_id = ?',
        whereArgs: ['legacy'],
      );
      final accountCursor = await transaction.query(
        'sync_state',
        columns: ['key'],
        where: 'key = ?',
        whereArgs: ['cursor:$accountId'],
      );
      if (accountCursor.isEmpty) {
        await transaction.update(
          'sync_state',
          {'key': 'cursor:$accountId'},
          where: 'key = ?',
          whereArgs: ['cursor'],
        );
      } else {
        await transaction.delete(
          'sync_state',
          where: 'key = ?',
          whereArgs: ['cursor'],
        );
      }
    });
    _activeAccountId = accountId;
  }

  void deactivateAccount() {
    _activeAccountId = 'anonymous';
  }

  static Future<void> _createTasksTable(DatabaseExecutor db) async {
    await db.execute('''
          CREATE TABLE tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task_uuid TEXT NOT NULL,
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
            account_id TEXT NOT NULL DEFAULT 'legacy',
            UNIQUE (task_uuid, account_id)
          )
        ''');
    await db.execute(
      'CREATE INDEX tasks_account_start ON tasks(account_id, start_datetime)',
    );
  }

  static Future<void> _createSyncOutboxTable(DatabaseExecutor db) async {
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
    await db.execute(
      'CREATE INDEX sync_outbox_task_created ON sync_outbox(task_uuid, created_at)',
    );
    await db.execute(
      'CREATE INDEX sync_outbox_account_created ON sync_outbox(account_id, created_at)',
    );
  }

  static Future<void> _createSyncStateTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE sync_state (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  static String _asUtcIsoString(Object? value) {
    return DateTime.parse(value.toString()).toUtc().toIso8601String();
  }

  Future<List<Map<String, Object?>>> getAllTasks() async {
    final db = await database;
    return db.query(
      'tasks',
      where: 'account_id = ? AND (deleted_at IS NULL OR sync_status = ?)',
      whereArgs: [_activeAccountId, 'conflict'],
      orderBy: 'start_datetime ASC, id DESC',
    );
  }

  Future<List<Map<String, Object?>>> getAllTaskRecords() async {
    final db = await database;
    return db.query(
      'tasks',
      where: 'account_id = ?',
      whereArgs: [_activeAccountId],
      orderBy: 'start_datetime ASC, id DESC',
    );
  }

  Future<Map<String, Object?>?> getTaskById(int id) async {
    final db = await database;
    final rows = await db.query(
      'tasks',
      where: 'id = ? AND account_id = ?',
      whereArgs: [id, _activeAccountId],
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<Map<String, Object?>?> getTaskByUuid(String taskUuid) async {
    final db = await database;
    final rows = await db.query(
      'tasks',
      where: 'task_uuid = ? AND account_id = ?',
      whereArgs: [taskUuid, _activeAccountId],
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<int> insertTaskWithOutbox(
    Map<String, Object?> task,
    Map<String, Object?> mutation,
  ) async {
    final db = await database;
    return db.transaction((transaction) async {
      final id = await transaction.insert('tasks', {
        ...task,
        'account_id': _activeAccountId,
      });
      await transaction.insert('sync_outbox', {
        ...mutation,
        'account_id': _activeAccountId,
      });
      return id;
    });
  }

  Future<void> enqueueSyncOperation(Map<String, Object?> mutation) async {
    final db = await database;
    await db.insert('sync_outbox', {
      ...mutation,
      'account_id': _activeAccountId,
    });
  }

  Future<void> updateTaskWithOutbox(
    int id,
    Map<String, Object?> task,
    Map<String, Object?> mutation,
  ) async {
    final db = await database;
    await db.transaction((transaction) async {
      final updated = await transaction.update(
        'tasks',
        {...task, 'account_id': _activeAccountId},
        where: 'id = ? AND account_id = ?',
        whereArgs: [id, _activeAccountId],
      );
      if (updated != 1) throw StateError('Task $id was not found.');
      await transaction.insert('sync_outbox', {
        ...mutation,
        'account_id': _activeAccountId,
      });
    });
  }

  Future<void> tombstoneTaskWithOutbox(
    int id,
    String taskUuid,
    DateTime deletedAt,
    Map<String, Object?> mutation,
  ) async {
    final db = await database;
    await db.transaction((transaction) async {
      final updated = await transaction.update(
        'tasks',
        {
          'deleted_at': deletedAt.toUtc().toIso8601String(),
          'local_updated_at': deletedAt.toUtc().toIso8601String(),
          'sync_status': 'pending',
          'sync_error': null,
          'conflict_data': null,
        },
        where: 'id = ? AND task_uuid = ? AND account_id = ?',
        whereArgs: [id, taskUuid, _activeAccountId],
      );
      if (updated != 1) throw StateError('Task $id was not found.');
      await transaction.insert('sync_outbox', {
        ...mutation,
        'account_id': _activeAccountId,
      });
    });
  }

  Future<List<Map<String, Object?>>> getSyncOutbox() async {
    final db = await database;
    return db.query(
      'sync_outbox',
      where: 'account_id = ?',
      whereArgs: [_activeAccountId],
      orderBy: 'created_at, rowid',
    );
  }

  Future<void> updateSyncOperation(
    String mutationId, {
    required int attempts,
    required String payload,
    int? baseVersion,
    String? lastError,
  }) async {
    final db = await database;
    final values = <String, Object?>{
      'attempts': attempts,
      'payload': payload,
      'last_error': lastError,
    };
    if (baseVersion != null) values['base_version'] = baseVersion;
    await db.update(
      'sync_outbox',
      values,
      where: 'mutation_id = ? AND account_id = ?',
      whereArgs: [mutationId, _activeAccountId],
    );
  }

  Future<void> removeSyncOperation(String mutationId) async {
    final db = await database;
    await db.delete(
      'sync_outbox',
      where: 'mutation_id = ? AND account_id = ?',
      whereArgs: [mutationId, _activeAccountId],
    );
  }

  Future<void> removeTaskSyncOperations(String taskUuid) async {
    final db = await database;
    await db.delete(
      'sync_outbox',
      where: 'task_uuid = ? AND account_id = ?',
      whereArgs: [taskUuid, _activeAccountId],
    );
  }

  Future<void> removeLocalTask(String taskUuid) async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete(
        'sync_outbox',
        where: 'task_uuid = ? AND account_id = ?',
        whereArgs: [taskUuid, _activeAccountId],
      );
      await transaction.delete(
        'tasks',
        where: 'task_uuid = ? AND account_id = ?',
        whereArgs: [taskUuid, _activeAccountId],
      );
    });
  }

  Future<void> resolveConflictWithLocal(
    String taskUuid,
    Map<String, Object?> task,
    Map<String, Object?> mutation,
  ) async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete(
        'sync_outbox',
        where: 'task_uuid = ? AND account_id = ?',
        whereArgs: [taskUuid, _activeAccountId],
      );
      final updated = await transaction.update(
        'tasks',
        {...task, 'account_id': _activeAccountId},
        where: 'task_uuid = ? AND account_id = ?',
        whereArgs: [taskUuid, _activeAccountId],
      );
      if (updated != 1) throw StateError('Task $taskUuid was not found.');
      await transaction.insert('sync_outbox', {
        ...mutation,
        'account_id': _activeAccountId,
      });
    });
  }

  Future<void> setTaskSyncState(
    String taskUuid, {
    required String status,
    String? error,
    String? conflictData,
    int? serverVersion,
    String? serverId,
    String? deletedAt,
  }) async {
    final values = <String, Object?>{
      'sync_status': status,
      'sync_error': error,
      'conflict_data': conflictData,
    };
    if (serverVersion != null) values['server_version'] = serverVersion;
    if (serverId != null) values['server_id'] = serverId;
    if (deletedAt != null) values['deleted_at'] = deletedAt;
    final db = await database;
    await db.update(
      'tasks',
      values,
      where: 'task_uuid = ? AND account_id = ?',
      whereArgs: [taskUuid, _activeAccountId],
    );
  }

  Future<void> applyRemoteTask(
    Map<String, Object?> remote, {
    bool force = false,
  }) async {
    final db = await database;
    await db.transaction((transaction) async {
      final taskUuid = remote['task_uuid'] as String;
      final rows = await transaction.query(
        'tasks',
        where: 'task_uuid = ? AND account_id = ?',
        whereArgs: [taskUuid, _activeAccountId],
      );
      final remoteVersion = (remote['version'] as num).toInt();
      final remoteUpdatedAt = remote['updated_at'] as String;
      final values = <String, Object?>{
        'task_uuid': taskUuid,
        'server_id': remote['server_id'] ?? taskUuid,
        'title': remote['title'],
        'note': remote['note'],
        'start_datetime': remote['start_datetime'],
        'end_datetime': remote['end_datetime'],
        'status': remote['status'],
        'created_at': remote['created_at'],
        'sync_status': 'synced',
        'server_version': remoteVersion,
        'local_updated_at': remoteUpdatedAt,
        'deleted_at': remote['deleted_at'],
        'sync_error': null,
        'conflict_data': null,
        'account_id': _activeAccountId,
      };

      if (rows.isEmpty) {
        await transaction.insert('tasks', values);
        return;
      }

      final local = rows.single;
      final isLocallyDirty =
          local['sync_status'] == 'pending' ||
          local['sync_status'] == 'failed' ||
          local['sync_status'] == 'conflict';
      final localVersion = (local['server_version'] as num?)?.toInt() ?? 0;
      if (isLocallyDirty && !force) {
        if (remoteVersion > localVersion) {
          await transaction.update(
            'tasks',
            {
              'server_id': remote['server_id'] ?? taskUuid,
              'server_version': remoteVersion,
              'sync_status': 'conflict',
              'conflict_data': jsonEncode(remote),
            },
            where: 'id = ?',
            whereArgs: [local['id']],
          );
        }
        return;
      }

      await transaction.update(
        'tasks',
        values,
        where: 'id = ?',
        whereArgs: [local['id']],
      );
    });
  }

  Future<int> getSyncCursor() async {
    final db = await database;
    final rows = await db.query(
      'sync_state',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_cursorKey],
    );
    return rows.isEmpty ? 0 : int.parse(rows.single['value']! as String);
  }

  Future<void> setSyncCursor(int cursor) async {
    final db = await database;
    await db.insert('sync_state', {
      'key': _cursorKey,
      'value': cursor.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  String get _cursorKey =>
      _activeAccountId == 'legacy' ? 'cursor' : 'cursor:$_activeAccountId';
}
