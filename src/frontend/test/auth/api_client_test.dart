import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend/core/errors/api_exception.dart';
import 'package:frontend/core/network/api_client.dart';

void main() {
  const baseUrl = 'http://example.test';

  test('retries GET once after 401 when refresh succeeds', () async {
    var gets = 0;
    final client = ApiClient(
      baseUrl: baseUrl,
      httpClient: MockClient((request) async {
        if (request.method == 'GET') {
          gets += 1;
          if (gets == 1) {
            return http.Response('unauthorized', 401);
          }
          return http.Response('[]', 200);
        }
        return http.Response('unexpected', 500);
      }),
    );
    client.accessToken = 'expired';
    var refreshCalls = 0;
    client.onTokenRefresh = () async {
      refreshCalls += 1;
      client.accessToken = 'new';
      return true;
    };

    final body = await client.get('/api/rabbits/');
    expect(body, '[]');
    expect(gets, 2);
    expect(refreshCalls, 1);
  });

  test('does not loop when refresh fails after 401', () async {
    var gets = 0;
    final client = ApiClient(
      baseUrl: baseUrl,
      httpClient: MockClient((request) async {
        gets += 1;
        return http.Response('unauthorized', 401);
      }),
    );
    client.accessToken = 'expired';
    var refreshCalls = 0;
    client.onTokenRefresh = () async {
      refreshCalls += 1;
      return false;
    };

    await expectLater(
      client.get('/api/rabbits/'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
    );
    expect(gets, 1);
    expect(refreshCalls, 1);
  });

  test('POST login path does not send Bearer when includeAuthHeader is false', () async {
    http.Request? captured;
    final client = ApiClient(
      baseUrl: baseUrl,
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({'ok': true}), 200);
      }),
    );
    client.accessToken = 'should-not-appear';

    await client.post(
      '/api/auth/login/',
      body: '{}',
      includeAuthHeader: false,
    );
    expect(captured, isNotNull);
    expect(captured!.headers['Authorization'], isNull);
  });

  test('GET wraps ClientException as ApiException with network code', () async {
    final client = ApiClient(
      baseUrl: baseUrl,
      httpClient: MockClient((request) async {
        throw http.ClientException('Connection refused', request.url);
      }),
    );

    await expectLater(
      client.get('/api/auth/bootstrap/'),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'network'),
      ),
    );
  });

  test('POST wraps timeout as ApiException with network code', () async {
    final client = ApiClient(
      baseUrl: baseUrl,
      timeout: const Duration(milliseconds: 20),
      httpClient: MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return http.Response('ok', 200);
      }),
    );

    await expectLater(
      client.post('/api/auth/login/', body: '{}', includeAuthHeader: false),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'network'),
      ),
    );
  });
}
