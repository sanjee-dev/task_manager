import 'package:task_manager/database/database_helper.dart';
import 'package:task_manager/models/task_model.dart';

class TaskRepository {
  const TaskRepository(this._database);

  final DatabaseHelper _database;

  Future<List<TaskModel>> getTasks() async {
    final rows = await _database.getAllTasks();
    return rows.map(TaskModel.fromMap).toList();
  }

  Future<TaskModel> createTask(TaskModel task) async {
    final id = await _database.insertTask(task.toMap()..remove('id'));
    return task.copyWith(id: id);
  }

  Future<void> updateTask(TaskModel task) async {
    final id = task.id;
    if (id == null) throw ArgumentError('Cannot update a task without an id.');
    await _database.updateTask(id, task.toMap()..remove('id'));
  }

  Future<void> deleteTask(int id) async {
    await _database.deleteTask(id);
  }
}
