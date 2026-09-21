import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/auth/presentation/screens/register_screen.dart';
import 'package:frontend/features/auth/presentation/screens/verify_email_screen.dart';
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

  Widget host(AuthViewModel vm, {required Widget home}) {
    return ChangeNotifierProvider<AuthViewModel>.value(
      value: vm,
      child: MaterialApp(home: home),
    );
  }

  FilledButton verifyButton(WidgetTester tester) {
    return tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Verificar'),
    );
  }

  testWidgets('shows the destination email and disables verify until 6 digits', (
    tester,
  ) async {
    final vm = viewModelWith(
      MockClient((request) async => http.Response('{}', 200)),
    );

    await tester.pumpWidget(
      host(
        vm,
        home: AuthVerifyEmailScreen(
          email: 'nueva@example.com',
          onVerify: ({required email, required code}) {
            return vm.verifyEmailCode(email: email, code: code);
          },
        ),
      ),
    );

    expect(find.text('Verifica tu correo'), findsOneWidget);
    expect(find.textContaining('nueva@example.com'), findsOneWidget);
    expect(verifyButton(tester).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('verificationCodeField')), '123');
    await tester.pump();
    expect(verifyButton(tester).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('verificationCodeField')), '123456');
    await tester.pump();
    expect(verifyButton(tester).onPressed, isNotNull);
  });

  testWidgets('invalid code shows catalog dialog without technical dump', (
    tester,
  ) async {
    final vm = viewModelWith(
      MockClient((request) async {
        return http.Response(
          jsonEncode({
            'detail': 'Invalid verification code.',
            'code': 'verification_code_invalid',
          }),
          400,
        );
      }),
    );

    await tester.pumpWidget(
      host(
        vm,
        home: AuthVerifyEmailScreen(
          email: 'nueva@example.com',
          onVerify: ({required email, required code}) {
            return vm.verifyEmailCode(email: email, code: code);
          },
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('verificationCodeField')),
      '000000',
    );
    await tester.pump();
    await tester.tap(find.text('Verificar'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('ApiException'), findsNothing);
    expect(find.textContaining('verification_code_invalid'), findsNothing);
    expect(find.textContaining('Invalid verification code'), findsNothing);
    expect(find.text('Código incorrecto'), findsOneWidget);
    expect(
      find.text(
        'El código ingresado no es válido. Revisa el correo e inténtalo nuevamente.',
      ),
      findsOneWidget,
    );
    expect(find.byType(AuthVerifyEmailScreen), findsOneWidget);
  });

  testWidgets('successful verify returns to login without opening the app', (
    tester,
  ) async {
    final vm = viewModelWith(
      MockClient((request) async {
        return http.Response(
          jsonEncode({
            'detail': 'Email verified successfully.',
            'verified': true,
          }),
          200,
        );
      }),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewModel>.value(
        value: vm,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AuthVerifyEmailScreen(
                          email: 'nueva@example.com',
                          onVerify: ({required email, required code}) {
                            return vm.verifyEmailCode(email: email, code: code);
                          },
                        ),
                      ),
                    );
                  },
                  child: const Text('abrir'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('verificationCodeField')),
      '482731',
    );
    await tester.pump();
    await tester.tap(find.text('Verificar'));
    await tester.pumpAndSettle();

    expect(find.byType(AuthVerifyEmailScreen), findsNothing);
    expect(find.textContaining('Correo verificado'), findsOneWidget);
    expect(vm.gate, isNot(AuthGate.app));
  });

  testWidgets('resend is blocked during cooldown then enabled', (tester) async {
    var resendCalls = 0;
    final vm = viewModelWith(
      MockClient((request) async => http.Response('{}', 200)),
    );

    await tester.pumpWidget(
      host(
        vm,
        home: AuthVerifyEmailScreen(
          email: 'nueva@example.com',
          resendCooldown: const Duration(seconds: 2),
          onResend: ({required email}) async {
            resendCalls += 1;
          },
        ),
      ),
    );

    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Reenviar código')).onPressed, isNull);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Reenviar código')).onPressed, isNotNull);

    await tester.tap(find.text('Reenviar código'));
    await tester.pump();
    expect(resendCalls, 1);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Reenviar código')).onPressed, isNull);
  });

  testWidgets('successful register opens the verify-email screen', (tester) async {
    final vm = viewModelWith(
      MockClient((request) async {
        expect(request.url.path, '/api/auth/register/');
        return http.Response(
          jsonEncode({
            'detail': 'Registration successful. Please verify your email to log in.',
            'verification_email_sent': true,
            'user': {'email': 'nueva@example.com', 'is_verified': false},
          }),
          201,
        );
      }),
    );

    await tester.pumpWidget(
      host(
        vm,
        home: AuthRegisterScreen(
          onSubmit: ({required email, required password}) {
            return vm.register(email: email, password: password);
          },
          onVerifyEmail: ({required email, required code}) {
            return vm.verifyEmailCode(email: email, code: code);
          },
          onResendVerification: ({required email}) {
            return vm.resendVerificationEmail(email: email);
          },
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField).at(0), 'nueva@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'password1');
    await tester.enterText(find.byType(TextFormField).at(2), 'password1');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Crear cuenta'));
    await tester.pumpAndSettle();

    expect(find.byType(AuthVerifyEmailScreen), findsOneWidget);
    expect(find.text('Verifica tu correo'), findsOneWidget);
    expect(find.textContaining('nueva@example.com'), findsOneWidget);
    expect(find.textContaining('ApiException'), findsNothing);
  });
}
