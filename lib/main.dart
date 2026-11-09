import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:task_manager/database/database_helper.dart';
import 'package:task_manager/providers/auth_provider.dart';
import 'package:task_manager/providers/task_provider.dart';
import 'package:task_manager/repositories/auth_repository.dart';
import 'package:task_manager/screens/auth_screens.dart';
import 'package:task_manager/screens/home_screen.dart';
import 'package:task_manager/services/auth_api_service.dart';
import 'package:task_manager/services/auth_token_store.dart';
import 'package:task_manager/utils/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final tokenStore = SecureAuthTokenStore();
  final authProvider = AuthProvider(
    AuthRepository(AuthApiService(), tokenStore),
    DatabaseHelper.instance,
  );
  runApp(
    ChangeNotifierProvider.value(
      value: authProvider,
      child: const TaskManagerApp(),
    ),
  );
  unawaited(authProvider.initialize());
}

class TaskManagerApp extends StatelessWidget {
  const TaskManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Task Manager',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      builder: (context, child) => Consumer<AuthProvider>(
        builder: (context, auth, _) {
          final taskProvider = auth.taskProvider;
          if (taskProvider == null) return child ?? const SizedBox.shrink();
          return ChangeNotifierProvider<TaskProvider>.value(
            value: taskProvider,
            child: child,
          );
        },
      ),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) => Consumer<AuthProvider>(
    builder: (context, auth, _) {
      if (auth.isLoading) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (auth.user == null || auth.taskProvider == null) {
        return LoginScreen(startupError: auth.startupError);
      }
      return const HomeScreen();
    },
  );
}
