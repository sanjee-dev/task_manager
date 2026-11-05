import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:task_manager/database/database_helper.dart';
import 'package:task_manager/providers/task_provider.dart';
import 'package:task_manager/repositories/task_repository.dart';
import 'package:task_manager/screens/home_screen.dart';
import 'package:task_manager/services/task_api_service.dart';
import 'package:task_manager/services/task_sync_service.dart';
import 'package:task_manager/utils/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final database = DatabaseHelper.instance;
  final syncService = TaskSyncService(database, TaskApiService());
  final repository = TaskRepository(database, syncService);
  runApp(
    ChangeNotifierProvider(
      create: (_) =>
          TaskProvider(repository, syncService: syncService)..loadTasks(),
      child: const TaskManagerApp(),
    ),
  );
}

class TaskManagerApp extends StatelessWidget {
  const TaskManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Task Manager',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const HomeScreen(),
    );
  }
}
