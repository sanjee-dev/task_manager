import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_manager/services/task_api_service.dart';

void main() {
  test('posts an idempotent mutation to the sync endpoint', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v1/sync');
      expect(request.headers['content-type'], 'application/json');
      expect(jsonDecode(request.body), {
        'mutations': [
          {'mutation_id': 'mutation-1', 'task_uuid': 'task-1'},
        ],
      });
      return http.Response(
        jsonEncode({
          'data': [
            {'mutation_id': 'mutation-1', 'status': 'synced', 'version': 1},
          ],
        }),
        200,
      );
    });
    final api = TaskApiService(
      client: client,
      baseUri: Uri.parse('https://example.test/api/v1/'),
    );

    final result = await api.pushMutation({
      'mutation_id': 'mutation-1',
      'task_uuid': 'task-1',
    });

    expect(result['status'], 'synced');
    api.close();
  });

  test('marks server failures as retryable API errors', () async {
    final api = TaskApiService(
      client: MockClient(
        (_) async => http.Response('Service unavailable', 503),
      ),
      baseUri: Uri.parse('https://example.test/api/v1/'),
    );

    await expectLater(
      api.getChanges(0),
      throwsA(
        isA<TaskApiException>()
            .having((error) => error.isRetryable, 'isRetryable', isTrue)
            .having((error) => error.statusCode, 'statusCode', 503),
      ),
    );
    api.close();
  });
}
