import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/app/app_root.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/auth/presentation/screens/login_screen.dart';
import 'package:frontend/services/auth_service.dart';
import 'package:frontend/services/auth_token_storage.dart';
import 'package:frontend/viewmodels/auth_viewmodel.dart';

void main() {
  const baseUrl = 'http://example.test';

  AuthViewModel viewModelWith(MockClient mock) {
    final api = ApiClient(httpClient: mock, baseUrl: baseUrl);
    return AuthViewModel(
      authService: AuthService(
        apiClient: api,
        tokenStorage: AuthTokenStorage.inMemory(),
      ),
    );
  }

  Future<void> fillAndSubmitLogin(WidgetTester tester) async {
    await tester.enterText(find.byType(TextFormField).at(0), 'a@b.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'badpass');
    await tester.pump();
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();
  }

  testWidgets('login does not show ApiException dump for invalid credentials', (
    tester,
  ) async {
    final vm = viewModelWith(
      MockClient((request) async {
        return http.Response(
          jsonEncode({
            'detail': 'Invalid credentials.',
            'code': 'invalid_credentials',
          }),
          400,
        );
      }),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewModel>.value(
        value: vm,
        child: MaterialApp(
          home: AuthLoginScreen(
            onSubmit: ({required email, required password}) {
              return vm.loginWithPassword(email: email, password: password);
            },
          ),
        ),
      ),
    );

    await fillAndSubmitLogin(tester);

    expect(find.textContaining('ApiException'), findsNothing);
    expect(find.textContaining('invalid_credentials'), findsNothing);
    expect(find.textContaining('Invalid credentials.'), findsNothing);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('No se pudo iniciar sesión'), findsOneWidget);
    expect(find.text('Entendido'), findsOneWidget);
    expect(
      find.text(
        'El correo o la contraseña son incorrectos. '
        'Verifica tus datos e inténtalo nuevamente.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('unverified login opens verify-email screen instead of technical dump', (
    tester,
  ) async {
    final vm = viewModelWith(
      MockClient((request) async {
        return http.Response(
          jsonEncode({
            'detail': 'Email not verified',
            'code': 'email_not_verified',
          }),
          400,
        );
      }),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewModel>.value(
        value: vm,
        child: MaterialApp(
          home: AuthLoginScreen(
            onSubmit: ({required email, required password}) {
              return vm.loginWithPassword(email: email, password: password);
            },
            onVerifyEmail: ({required email, required code}) {
              return vm.verifyEmailCode(email: email, code: code);
            },
            onResendVerification: ({required email}) {
              return vm.resendVerificationEmail(email: email);
            },
          ),
        ),
      ),
    );

    await fillAndSubmitLogin(tester);

    expect(find.textContaining('ApiException'), findsNothing);
    expect(find.textContaining('email_not_verified'), findsNothing);
    expect(find.text('Verifica tu correo'), findsOneWidget);
    expect(find.textContaining('a@b.com'), findsOneWidget);
  });

  testWidgets('AppRoot login does not snackbar raw backend JSON', (
    tester,
  ) async {
    final vm = viewModelWith(
      MockClient((request) async {
        if (request.url.path == '/api/auth/login/') {
          return http.Response(
            jsonEncode({
              'detail': 'Invalid credentials.',
              'code': 'invalid_credentials',
            }),
            400,
          );
        }
        return http.Response(
          jsonEncode({
            'session_valid': false,
            'auth_required': true,
            'biometric_available': false,
          }),
          200,
        );
      }),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewModel>.value(
        value: vm,
        child: const MaterialApp(
          home: AppRoot(home: Scaffold(body: Text('home'))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await fillAndSubmitLogin(tester);

    expect(find.textContaining('ApiException'), findsNothing);
    expect(find.textContaining('invalid_credentials'), findsNothing);
    expect(find.textContaining('Invalid credentials.'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('No se pudo iniciar sesión'), findsOneWidget);
    expect(find.text('Entendido'), findsOneWidget);
    expect(
      find.text(
        'El correo o la contraseña son incorrectos. '
        'Verifica tus datos e inténtalo nuevamente.',
      ),
      findsOneWidget,
    );
  });
}
