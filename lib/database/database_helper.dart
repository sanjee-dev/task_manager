import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();
  static const _databaseName = 'task_manager.db';
  static const _databaseVersion = 1;
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final databasePath = await getDatabasesPath();
    _database = await openDatabase(
      join(databasePath, _databaseName),
      version: _databaseVersion,
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
      },
    );
    return _database!;
  }

  Future<List<Map<String, Object?>>> getAllTasks() async {
    final db = await database;
    return db.query('tasks', orderBy: 'start_datetime ASC, id DESC');
  }

  Future<int> insertTask(Map<String, Object?> task) async {
    final db = await database;
    return db.insert('tasks', task, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<int> updateTask(int id, Map<String, Object?> task) async {
    final db = await database;
    return db.update('tasks', task, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteTask(int id) async {
    final db = await database;
    return db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }
}
