import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_manager/screens/auth_screens.dart';

void main() {
  testWidgets('login asks for username and password without OTP', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('Task Manager'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Forgot Password?'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.textContaining('OTP'), findsNothing);
  });

  testWidgets('registration asks only for full name and email', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RegisterScreen()));

    expect(find.text('Full name'), findsOneWidget);
    expect(find.text('Email address'), findsOneWidget);
    expect(find.text('Register'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.textContaining('Password'), findsNothing);
    expect(find.textContaining('code'), findsNothing);
  });
}
