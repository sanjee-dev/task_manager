import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager/services/auth_api_service.dart';

void main() {
  test(
    'uses the auth API root and bearer token for profile requests',
    () async {
      const token = 'test-token';
      final api = AuthApiService(
        baseUri: Uri.parse('https://example.test/api/'),
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url, Uri.parse('https://example.test/api/user'));
          expect(request.headers['authorization'], 'Bearer $token');
          return http.Response(
            jsonEncode({
              'data': {
                'id': 42,
                'name': 'Test User',
                'email': 'test@example.test',
                'username': 'test_user',
              },
            }),
            200,
          );
        }),
      );

      final user = await api.getUser(token);

      expect(user.id, 42);
      expect(user.email, 'test@example.test');
      expect(user.username, 'test_user');
      api.close();
    },
  );

  test(
    'registers with name and email and logs in with username and password',
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
                    'username': 'new_user',
                  },
                },
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({'message': 'Credentials emailed.'}),
            201,
          );
        }),
      );

      await api.register(name: 'New User', email: 'new@example.test');
      final session = await api.login('new_user', 'StrongPassword123!');

      expect(requests[0].url.path, '/api/register');
      expect(jsonDecode(requests[0].body), {
        'name': 'New User',
        'email': 'new@example.test',
      });
      expect(requests[1].url.path, '/api/login');
      expect(jsonDecode(requests[1].body), {
        'username': 'new_user',
        'password': 'StrongPassword123!',
      });
      expect(session.token, 'issued-token');
      expect(session.user.id, 7);
      expect(session.user.username, 'new_user');
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
      api.login('a_username', 'bad'),
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
