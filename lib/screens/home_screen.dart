import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:task_manager/models/task_model.dart';
import 'package:task_manager/screens/auth_screens.dart';
import 'package:task_manager/providers/task_provider.dart';
import 'package:task_manager/screens/add_task_screen.dart';
import 'package:task_manager/screens/edit_task_screen.dart';
import 'package:task_manager/screens/task_details_screen.dart';
import 'package:task_manager/utils/app_colors.dart';
import 'package:task_manager/widgets/empty_state.dart';
import 'package:task_manager/widgets/task_card.dart';
import 'package:task_manager/widgets/task_summary_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _addTask(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const AddTaskScreen(),
      ),
    );
  }

  Future<void> _deleteTask(
    BuildContext context,
    TaskProvider provider,
    TaskModel task,
  ) async {
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
      await provider.deleteTask(task.id!);
      if (context.mounted) {
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

  Future<void> _changeStatus(
    BuildContext context,
    TaskProvider provider,
    TaskModel task,
    TaskStatus status,
  ) async {
    try {
      await provider.updateStatus(task, status);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update task: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TaskProvider>(
      builder: (context, provider, _) {
        final tasks = provider.visibleTasks;
        return Scaffold(
          floatingActionButton: FloatingActionButton(
            onPressed: () => _addTask(context),
            tooltip: 'Add task',
            child: const Icon(Icons.add),
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Task Manager',
                                        style: TextStyle(
                                          color: AppColors.ink,
                                          fontSize: 26,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'A little progress adds up.',
                                        style: TextStyle(
                                          color: AppColors.muted,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Profile and settings',
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const ProfileScreen(),
                                    ),
                                  ),
                                  icon: const CircleAvatar(
                                    radius: 22,
                                    backgroundColor: Color(0xFFEAF1FF),
                                    child: Icon(
                                      Icons.person_outline_rounded,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Text(
                              '${provider.totalCount} ${provider.totalCount == 1 ? 'task' : 'tasks'}',
                              style: const TextStyle(
                                color: AppColors.ink,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                TaskSummaryCard(
                                  label: 'Pending',
                                  count: provider.countFor(TaskStatus.pending),
                                  color: AppColors.pending,
                                  icon: Icons.schedule_rounded,
                                ),
                                const SizedBox(width: 10),
                                TaskSummaryCard(
                                  label: 'Done',
                                  count: provider.countFor(TaskStatus.done),
                                  color: AppColors.done,
                                  icon: Icons.check_circle_outline_rounded,
                                ),
                              ],
                            ),
                            if (provider.isSyncing) ...[
                              const SizedBox(height: 12),
                              const LinearProgressIndicator(),
                            ] else if (provider.syncError != null ||
                                provider.failedSyncCount > 0) ...[
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      provider.syncError ??
                                          '${provider.failedSyncCount} task change(s) need a sync retry.',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: provider.retrySync,
                                    child: const Text('Retry sync'),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 21),
                            TextField(
                              onChanged: provider.setSearchQuery,
                              decoration: const InputDecoration(
                                hintText: 'Search tasks',
                                prefixIcon: Icon(Icons.search_rounded),
                              ),
                            ),
                            const SizedBox(height: 14),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _FilterChip(
                                    label: 'All',
                                    selected: provider.statusFilter == null,
                                    onSelected: () =>
                                        provider.setStatusFilter(null),
                                  ),
                                  for (final status in TaskStatus.values)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: _FilterChip(
                                        label: status.label,
                                        selected:
                                            provider.statusFilter == status,
                                        onSelected: () =>
                                            provider.setStatusFilter(status),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              provider.statusFilter == null
                                  ? 'Your tasks'
                                  : '${provider.statusFilter!.label} tasks',
                              style: const TextStyle(
                                color: AppColors.ink,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (provider.isLoading)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (provider.errorMessage != null)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  color: Colors.red,
                                  size: 36,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  provider.errorMessage!,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 14),
                                OutlinedButton(
                                  onPressed: provider.loadTasks,
                                  child: const Text('Try again'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else if (tasks.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: EmptyState(
                          title: provider.totalCount == 0
                              ? 'No tasks yet'
                              : 'No tasks found',
                          message: provider.totalCount == 0
                              ? 'Create your first task and make today count.'
                              : 'Try a different search or status filter.',
                          onAdd: provider.totalCount == 0
                              ? () => _addTask(context)
                              : null,
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
                        sliver: SliverList.separated(
                          itemCount: tasks.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final task = tasks[index];
                            return TaskCard(
                              task: task,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => TaskDetailsScreen(task: task),
                                ),
                              ),
                              onEdit: () => showEditTaskDialog(context, task),
                              onDelete: () =>
                                  _deleteTask(context, provider, task),
                              onStatusChanged: (status) => _changeStatus(
                                context,
                                provider,
                                task,
                                status,
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppColors.muted,
        fontWeight: FontWeight.w600,
      ),
      selectedColor: AppColors.primary,
      backgroundColor: Colors.white,
      side: BorderSide(
        color: selected ? AppColors.primary : const Color(0xFFE2E8F0),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}
