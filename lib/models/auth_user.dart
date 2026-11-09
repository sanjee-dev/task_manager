class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    this.username = '',
  });

  final int id;
  final String name;
  final String email;
  final String username;

  factory AuthUser.fromJson(Map<String, Object?> json) => AuthUser(
    id: (json['id'] as num).toInt(),
    name: json['name'] as String,
    email: json['email'] as String,
    username: json['username'] as String? ?? '',
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'username': username,
  };
}
