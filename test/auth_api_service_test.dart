import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager/services/auth_api_service.dart';

void main() {
  test(
    'uses the auth API root and bearer token for profile requests',
    () async {
      final api = AuthApiService(
        baseUri: Uri.parse('https://example.test/api/'),
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url, Uri.parse('https://example.test/api/user'));
          expect(request.headers['authorization'], 'Bearer test-token');
          return http.Response(
            jsonEncode({
              'data': {
                'id': 42,
                'name': 'Test User',
                'email': 'test@example.test',
              },
            }),
            200,
          );
        }),
      );

      final user = await api.getUser('test-token');

      expect(user.id, 42);
      expect(user.email, 'test@example.test');
      api.close();
    },
  );

  test(
    'posts registration and login credentials to the auth endpoints',
    () async {
      final requests = <http.Request>[];
      final api = AuthApiService(
        baseUri: Uri.parse('https://example.test/api/'),
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/login')) {
            return http.Response(
              jsonEncode({
                'data': {
                  'token': 'issued-token',
                  'user': {
                    'id': 7,
                    'name': 'New User',
                    'email': 'new@example.test',
                  },
                },
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({'message': 'Verification sent.'}),
            201,
          );
        }),
      );

      await api.register(
        name: 'New User',
        email: 'new@example.test',
        password: 'StrongPassword123!',
      );
      final session = await api.login('new@example.test', 'StrongPassword123!');

      expect(requests[0].url.path, '/api/register');
      expect(
        jsonDecode(requests[0].body)['password_confirmation'],
        'StrongPassword123!',
      );
      expect(requests[1].url.path, '/api/login');
      expect(session.token, 'issued-token');
      expect(session.user.id, 7);
      api.close();
    },
  );

  test('exposes backend validation messages and status codes', () async {
    final api = AuthApiService(
      baseUri: Uri.parse('https://example.test/api/'),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'message': 'The provided credentials are incorrect.'}),
          401,
        ),
      ),
    );

    await expectLater(
      api.login('user@example.test', 'bad'),
      throwsA(
        isA<AuthApiException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having(
              (error) => error.message,
              'message',
              'The provided credentials are incorrect.',
            ),
      ),
    );
    api.close();
  });
}
