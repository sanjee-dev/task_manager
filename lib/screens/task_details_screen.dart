import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:task_manager/models/task_model.dart';
import 'package:task_manager/providers/task_provider.dart';
import 'package:task_manager/screens/edit_task_screen.dart';
import 'package:task_manager/utils/app_colors.dart';
import 'package:task_manager/utils/date_time_helper.dart';
import 'package:task_manager/widgets/status_chip.dart';

class TaskDetailsScreen extends StatelessWidget {
  const TaskDetailsScreen({super.key, required this.task});

  final TaskModel task;

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text('“${task.title}” will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted || task.id == null) return;
    try {
      await context.read<TaskProvider>().deleteTask(task.id!);
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Task deleted')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete task: $error')),
        );
      }
    }
  }

  Future<void> _changeStatus(BuildContext context, TaskStatus status) async {
    try {
      final provider = context.read<TaskProvider>();
      final currentTask = provider.tasks.firstWhere(
        (current) => current.id == task.id,
        orElse: () => task,
      );
      await provider.updateStatus(currentTask, status);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update task: $error')),
        );
      }
    }
  }

  Future<void> _resolveConflict(
    BuildContext context, {
    required bool keepLocal,
  }) async {
    final taskUuid = task.taskUuid;
    if (taskUuid == null) return;
    try {
      final provider = context.read<TaskProvider>();
      await provider.resolveConflict(taskUuid, keepLocal: keepLocal);
      if (!keepLocal &&
          context.mounted &&
          !provider.tasks.any((current) => current.taskUuid == taskUuid)) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not resolve conflict: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTask = context.select<TaskProvider, TaskModel>(
      (provider) => provider.tasks.firstWhere(
        (current) => current.id == task.id,
        orElse: () => task,
      ),
    );
    final serverTitle = _conflictTitle(currentTask.conflictData);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Task details'),
        actions: [
          IconButton(
            tooltip: 'Edit task',
            onPressed: () => showEditTaskDialog(context, currentTask),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Delete task',
            onPressed: () => _delete(context),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          if (currentTask.syncStatus == TaskSyncStatus.conflict)
            Card(
              color: const Color(0xFFFFF4E5),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'This task changed on the server.',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Choose which version to keep. Your local version is preserved until you decide.',
                    ),
                    if (serverTitle != null) ...[
                      const SizedBox(height: 8),
                      Text('Server title: $serverTitle'),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () =>
                              _resolveConflict(context, keepLocal: false),
                          child: const Text('Use server version'),
                        ),
                        FilledButton(
                          onPressed: () =>
                              _resolveConflict(context, keepLocal: true),
                          child: const Text('Keep my version'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currentTask.title,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (currentTask.note != null &&
                      currentTask.note!.trim().isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      currentTask.note!,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  _DetailRow(
                    icon: Icons.play_arrow_rounded,
                    label: 'Starts',
                    value:
                        '${DateTimeHelper.date(currentTask.startDateTime)} at ${DateTimeHelper.time(currentTask.startDateTime)}',
                  ),
                  const SizedBox(height: 16),
                  _DetailRow(
                    icon: Icons.flag_outlined,
                    label: 'Ends',
                    value:
                        '${DateTimeHelper.date(currentTask.endDateTime)} at ${DateTimeHelper.time(currentTask.endDateTime)}',
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Status',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: TaskStatus.values.map((status) {
                      return ActionChip(
                        label: StatusChip(status: status),
                        onPressed: currentTask.status == status
                            ? null
                            : () => _changeStatus(context, status),
                        side: BorderSide(
                          color: currentTask.status == status
                              ? AppColors.primary
                              : const Color(0xFFE2E8F0),
                        ),
                        backgroundColor: currentTask.status == status
                            ? const Color(0xFFEAF1FF)
                            : Colors.white,
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => showEditTaskDialog(context, currentTask),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit task'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _delete(context),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete task'),
          ),
        ],
      ),
    );
  }

  String? _conflictTitle(String? conflictData) {
    if (conflictData == null) return null;
    try {
      final decoded = jsonDecode(conflictData);
      if (decoded is Map<String, dynamic>) return decoded['title']?.toString();
    } on FormatException {
      return null;
    }
    return null;
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
