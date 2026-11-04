enum TaskStatus {
  pending('pending', 'Pending'),
  done('done', 'Done');

  const TaskStatus(this.value, this.label);

  final String value;
  final String label;

  static TaskStatus fromValue(String value) => TaskStatus.values.firstWhere(
    (status) => status.value == value,
    orElse: () => TaskStatus.pending,
  );
}

class TaskModel {
  const TaskModel({
    this.id,
    required this.title,
    this.note,
    required this.startDateTime,
    required this.endDateTime,
    this.status = TaskStatus.pending,
    required this.createdAt,
  });

  final int? id;
  final String title;
  final String? note;
  final DateTime startDateTime;
  final DateTime endDateTime;
  final TaskStatus status;
  final DateTime createdAt;

  TaskModel copyWith({
    int? id,
    String? title,
    String? note,
    DateTime? startDateTime,
    DateTime? endDateTime,
    TaskStatus? status,
    DateTime? createdAt,
    bool clearNote = false,
  }) {
    return TaskModel(
      id: id ?? this.id,
      title: title ?? this.title,
      note: clearNote ? null : note ?? this.note,
      startDateTime: startDateTime ?? this.startDateTime,
      endDateTime: endDateTime ?? this.endDateTime,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'note': note,
    'start_datetime': startDateTime.toIso8601String(),
    'end_datetime': endDateTime.toIso8601String(),
    'status': status.value,
    'created_at': createdAt.toIso8601String(),
  };

  factory TaskModel.fromMap(Map<String, Object?> map) => TaskModel(
    id: map['id'] as int?,
    title: map['title'] as String,
    note: map['note'] as String?,
    startDateTime: DateTime.parse(map['start_datetime'] as String),
    endDateTime: DateTime.parse(map['end_datetime'] as String),
    status: TaskStatus.fromValue(map['status'] as String),
    createdAt: DateTime.parse(map['created_at'] as String),
  );
}
