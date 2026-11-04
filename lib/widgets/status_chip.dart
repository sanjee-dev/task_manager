import 'package:flutter/material.dart';
import 'package:task_manager/models/task_model.dart';
import 'package:task_manager/utils/app_colors.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final TaskStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      TaskStatus.pending => AppColors.pending,
      TaskStatus.done => AppColors.done,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
