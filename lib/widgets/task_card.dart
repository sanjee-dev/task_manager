import 'package:flutter/material.dart';
import 'package:task_manager/models/task_model.dart';
import 'package:task_manager/utils/app_colors.dart';
import 'package:task_manager/utils/date_time_helper.dart';
import 'package:task_manager/widgets/status_chip.dart';

class TaskCard extends StatelessWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onStatusChanged,
  });

  final TaskModel task;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<TaskStatus> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final isDone = task.status == TaskStatus.done;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 8, 15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: IconButton(
                  tooltip: isDone ? 'Mark as pending' : 'Mark as done',
                  onPressed: () => onStatusChanged(
                    isDone ? TaskStatus.pending : TaskStatus.done,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  icon: Icon(
                    isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 23,
                    color: isDone ? AppColors.done : const Color(0xFFB4BECC),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDone ? AppColors.muted : AppColors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (task.note != null && task.note!.trim().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        task.note!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        const Icon(
                          Icons.schedule_rounded,
                          size: 14,
                          color: AppColors.muted,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            DateTimeHelper.range(
                              task.startDateTime,
                              task.endDateTime,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    StatusChip(status: task.status),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Task actions',
                onSelected: (action) {
                  if (action == 'edit') onEdit();
                  if (action == 'delete') onDelete();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Edit'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('Delete'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
