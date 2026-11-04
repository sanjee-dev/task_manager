import 'package:flutter/material.dart';
import 'package:task_manager/utils/app_colors.dart';

class TaskSummaryCard extends StatelessWidget {
  const TaskSummaryCard({
    super.key,
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  final String label;
  final int count;
  final Color color;
  final IconData icon;

  Color get _background => switch (color) {
    AppColors.pending => const Color(0xFFFFF8E8),
    _ => const Color(0xFFEBF8F1),
  };

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 19, color: color),
            const SizedBox(height: 10),
            Text(
              '$count',
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 21,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              label,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
