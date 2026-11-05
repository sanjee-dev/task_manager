import 'package:flutter/material.dart';
import 'package:task_manager/models/task_model.dart';
import 'package:task_manager/utils/app_colors.dart';
import 'package:task_manager/utils/date_time_helper.dart';
import 'package:task_manager/widgets/custom_text_field.dart';
import 'package:task_manager/widgets/status_chip.dart';

class TaskForm extends StatefulWidget {
  const TaskForm({super.key, this.task, required this.onSave});

  final TaskModel? task;
  final Future<void> Function(TaskModel) onSave;

  @override
  State<TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<TaskForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  late DateTime _startDateTime;
  late DateTime _endDateTime;
  late TaskStatus _status;
  String? _dateTimeError;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    final now = DateTime.now();
    _titleController = TextEditingController(text: task?.title ?? '');
    _noteController = TextEditingController(text: task?.note ?? '');
    _startDateTime =
        task?.startDateTime.toLocal() ??
        DateTime(now.year, now.month, now.day, now.hour, now.minute);
    _endDateTime =
        task?.endDateTime.toLocal() ??
        _startDateTime.add(const Duration(hours: 1));
    _status = task?.status ?? TaskStatus.pending;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final current = isStart ? _startDateTime : _endDateTime;
    final selected = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected == null || !mounted) return;
    setState(() {
      final next = DateTime(
        selected.year,
        selected.month,
        selected.day,
        current.hour,
        current.minute,
      );
      if (isStart) {
        _startDateTime = next;
      } else {
        _endDateTime = next;
      }
      _validateDateTime();
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final current = isStart ? _startDateTime : _endDateTime;
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (selected == null || !mounted) return;
    setState(() {
      final next = DateTime(
        current.year,
        current.month,
        current.day,
        selected.hour,
        selected.minute,
      );
      if (isStart) {
        _startDateTime = next;
      } else {
        _endDateTime = next;
      }
      _validateDateTime();
    });
  }

  void _validateDateTime() {
    _dateTimeError = _endDateTime.isBefore(_startDateTime)
        ? 'End date and time must be on or after the start.'
        : null;
  }

  Future<void> _submit() async {
    final isFormValid = _formKey.currentState?.validate() ?? false;
    setState(_validateDateTime);
    if (!isFormValid || _dateTimeError != null) return;
    setState(() => _isSaving = true);
    final task = TaskModel(
      id: widget.task?.id,
      taskUuid: widget.task?.taskUuid,
      serverId: widget.task?.serverId,
      title: _titleController.text.trim(),
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
      startDateTime: _startDateTime,
      endDateTime: _endDateTime,
      status: _status,
      createdAt: widget.task?.createdAt ?? DateTime.now(),
      syncStatus: widget.task?.syncStatus ?? TaskSyncStatus.pending,
      serverVersion: widget.task?.serverVersion ?? 0,
      localUpdatedAt: widget.task?.localUpdatedAt,
      deletedAt: widget.task?.deletedAt,
      syncError: widget.task?.syncError,
      conflictData: widget.task?.conflictData,
    );
    try {
      await widget.onSave(task);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _dateTimeRow({
    required String label,
    required DateTime value,
    required VoidCallback onDate,
    required VoidCallback onTime,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: OutlinedButton.icon(
                onPressed: onDate,
                icon: const Icon(Icons.calendar_today_outlined, size: 17),
                label: Text(DateTimeHelper.date(value)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.ink,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              flex: 2,
              child: OutlinedButton.icon(
                onPressed: onTime,
                icon: const Icon(Icons.access_time, size: 17),
                label: Text(DateTimeHelper.time(value)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.ink,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 14,
                  ),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.task != null;
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          CustomTextField(
            controller: _titleController,
            label: 'Task title',
            hint: 'What needs to get done?',
            maxLength: 255,
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Please enter a task title.'
                : value.trim().length > 255
                ? 'Task titles must be 255 characters or fewer.'
                : null,
          ),
          const SizedBox(height: 16),
          CustomTextField(
            controller: _noteController,
            label: 'Description (optional)',
            hint: 'Add a note',
            maxLines: 4,
          ),
          const SizedBox(height: 22),
          _dateTimeRow(
            label: 'From',
            value: _startDateTime,
            onDate: () => _pickDate(isStart: true),
            onTime: () => _pickTime(isStart: true),
          ),
          const SizedBox(height: 18),
          _dateTimeRow(
            label: 'To',
            value: _endDateTime,
            onDate: () => _pickDate(isStart: false),
            onTime: () => _pickTime(isStart: false),
          ),
          if (_dateTimeError != null) ...[
            const SizedBox(height: 8),
            Text(
              _dateTimeError!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ],
          if (isEditing) ...[
            const SizedBox(height: 22),
            const Text(
              'Status',
              style: TextStyle(
                color: AppColors.ink,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: TaskStatus.values.map((status) {
                return ChoiceChip(
                  label: StatusChip(status: status),
                  selected: status == _status,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _status = status),
                  side: BorderSide(
                    color: _status == status
                        ? AppColors.primary
                        : const Color(0xFFE2E8F0),
                  ),
                  backgroundColor: Colors.white,
                  selectedColor: const Color(0xFFEAF1FF),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _isSaving ? null : _submit,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(isEditing ? 'Save changes' : 'Create task'),
          ),
        ],
      ),
    );
  }
}
