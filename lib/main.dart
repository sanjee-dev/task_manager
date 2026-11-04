import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:task_manager/database/database_helper.dart';
import 'package:task_manager/providers/task_provider.dart';
import 'package:task_manager/repositories/task_repository.dart';
import 'package:task_manager/screens/home_screen.dart';
import 'package:task_manager/utils/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) =>
          TaskProvider(TaskRepository(DatabaseHelper.instance))..loadTasks(),
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
