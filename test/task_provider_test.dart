import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:task_manager/models/task_model.dart';
import 'package:task_manager/providers/task_provider.dart';
import 'package:task_manager/repositories/task_repository.dart';
import 'package:task_manager/screens/edit_task_screen.dart';
import 'package:task_manager/widgets/task_card.dart';

void main() {
  late _FakeTaskRepository repository;
  late TaskProvider provider;

  setUp(() {
    repository = _FakeTaskRepository();
    provider = TaskProvider(repository);
  });

  tearDown(() {
    provider.dispose();
  });

  test(
    'creates, reads, updates and deletes tasks through the repository',
    () async {
      final task = _task('Plan the week');
      await provider.addTask(task);

      expect(provider.totalCount, 1);
      expect(provider.tasks.single.title, 'Plan the week');
      expect(provider.tasks.single.id, isNotNull);

      final created = provider.tasks.single;
      await provider.updateTask(created.copyWith(title: 'Plan the month'));
      expect(provider.tasks.single.title, 'Plan the month');

      await provider.deleteTask(created.id!);
      expect(provider.tasks, isEmpty);

      await provider.addTask(task);
      final reloadedProvider = TaskProvider(repository);
      await reloadedProvider.loadTasks();
      expect(reloadedProvider.tasks.single.title, 'Plan the week');
      reloadedProvider.dispose();
    },
  );

  test(
    'toggles between pending and done and computes summary counts',
    () async {
      await provider.addTask(_task('Review notes'));
      var task = provider.tasks.single;

      await provider.updateStatus(task, TaskStatus.done);
      task = provider.tasks.single;
      expect(task.status, TaskStatus.done);
      expect(provider.countFor(TaskStatus.done), 1);

      await provider.updateStatus(task, TaskStatus.pending);
      expect(provider.tasks.single.status, TaskStatus.pending);
      expect(provider.countFor(TaskStatus.done), 0);
      expect(provider.countFor(TaskStatus.pending), 1);
    },
  );

  test('search and status filter combine', () async {
    await provider.addTask(_task('Write project plan'));
    await provider.addTask(_task('Review project plan'));
    await provider.addTask(
      _task('Write weekly summary').copyWith(status: TaskStatus.done),
    );

    provider.setSearchQuery('write');
    provider.setStatusFilter(TaskStatus.done);

    expect(provider.visibleTasks.map((task) => task.title), [
      'Write weekly summary',
    ]);

    provider.setStatusFilter(null);
    expect(provider.visibleTasks, hasLength(2));
  });

  testWidgets('task circle toggles between pending and done', (tester) async {
    final statuses = <TaskStatus>[];
    var status = TaskStatus.pending;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => TaskCard(
              task: _task('Tap to complete').copyWith(status: status),
              onTap: () {},
              onEdit: () {},
              onDelete: () {},
              onStatusChanged: (nextStatus) {
                statuses.add(nextStatus);
                setState(() => status = nextStatus);
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Mark as done'));
    await tester.pumpAndSettle();
    expect(statuses, [TaskStatus.done]);
    expect(find.byTooltip('Mark as pending'), findsOneWidget);

    await tester.tap(find.byTooltip('Mark as pending'));
    await tester.pumpAndSettle();
    expect(statuses, [TaskStatus.done, TaskStatus.pending]);
  });

  testWidgets('edit action opens the task form in a popup', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showEditTaskDialog(context, _task('Edit me')),
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Edit task'), findsOneWidget);
    expect(find.text('Edit me'), findsOneWidget);
  });
}

TaskModel _task(String title) {
  final start = DateTime(2026, 11, 4, 9);
  return TaskModel(
    title: title,
    startDateTime: start,
    endDateTime: start.add(const Duration(hours: 1)),
    createdAt: start,
  );
}

class _FakeTaskRepository implements TaskRepository {
  final Map<int, TaskModel> _tasks = {};
  var _nextId = 1;

  @override
  Future<List<TaskModel>> getTasks() async => _tasks.values.toList();

  @override
  Future<TaskModel> createTask(TaskModel task) async {
    final savedTask = task.copyWith(id: _nextId++);
    _tasks[savedTask.id!] = savedTask;
    return savedTask;
  }

  @override
  Future<void> updateTask(TaskModel task) async {
    _tasks[task.id!] = task;
  }

  @override
  Future<void> deleteTask(int id) async {
    _tasks.remove(id);
  }

  @override
  Future<void> resolveConflict(
    String taskUuid, {
    required bool keepLocal,
  }) async {}
}
