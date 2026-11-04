import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:task_manager/models/task_model.dart';
import 'package:task_manager/providers/task_provider.dart';
import 'package:task_manager/widgets/task_form.dart';

Future<void> showEditTaskDialog(BuildContext context, TaskModel task) {
  final screenSize = MediaQuery.sizeOf(context);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: SizedBox(
        width: screenSize.width < 592 ? screenSize.width - 32 : 560,
        height: screenSize.height * 0.88,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Edit task',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: TaskForm(
                task: task,
                onSave: (updatedTask) async {
                  try {
                    await context.read<TaskProvider>().updateTask(updatedTask);
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Changes saved')),
                      );
                    }
                  } catch (error) {
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(
                          content: Text('Could not save changes: $error'),
                        ),
                      );
                    }
                  }
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
