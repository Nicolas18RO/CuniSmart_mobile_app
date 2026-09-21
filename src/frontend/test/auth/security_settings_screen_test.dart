import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/auth/presentation/screens/security_settings_screen.dart';
import 'package:frontend/services/auth_service.dart';
import 'package:frontend/services/auth_token_storage.dart';
import 'package:frontend/viewmodels/auth_viewmodel.dart';

import 'fake_device_authenticator.dart';

void main() {
  testWidgets('security settings exposes voluntary biometric toggle', (tester) async {
    final api = ApiClient(
      httpClient: MockClient((request) async {
        return http.Response(jsonEncode({'biometric_enabled': false}), 200);
      }),
      baseUrl: 'http://example.test',
    );
    final vm = AuthViewModel(
      authService: AuthService(
        apiClient: api,
        tokenStorage: AuthTokenStorage.inMemory(),
      ),
      deviceAuth: FakeDeviceAuthenticator(available: true),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewModel>.value(
        value: vm,
        child: const MaterialApp(home: AuthSecuritySettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Desbloqueo biométrico'), findsWidgets);
    expect(find.byType(SwitchListTile), findsOneWidget);
  });
}
