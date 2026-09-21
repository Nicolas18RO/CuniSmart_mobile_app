import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:frontend/features/auth/presentation/screens/register_screen.dart';
import 'package:frontend/features/auth/presentation/screens/reset_password_screen.dart';
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

  testWidgets('register does not show ApiException dump for duplicate email', (
    tester,
  ) async {
    final vm = viewModelWith(
      MockClient((request) async {
        return http.Response(
          jsonEncode({
            'detail': 'A user with this email already exists.',
            'code': 'validation_error',
          }),
          400,
        );
      }),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewModel>.value(
        value: vm,
        child: MaterialApp(
          home: AuthRegisterScreen(
            onSubmit: ({required email, required password}) {
              return vm.register(email: email, password: password);
            },
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField).at(0), 'dup@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'password1');
    await tester.enterText(find.byType(TextFormField).at(2), 'password1');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Crear cuenta'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('ApiException'), findsNothing);
    expect(find.textContaining('already exists'), findsNothing);
    expect(
      find.text(
        'Este correo ya está registrado. Intenta iniciar sesión o recuperar tu contraseña.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Crear cuenta'), findsOneWidget);
  });

  testWidgets('forgot password 500 does not show raw backend JSON', (
    tester,
  ) async {
    final vm = viewModelWith(
      MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'Internal Server Error'}),
          500,
        );
      }),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewModel>.value(
        value: vm,
        child: MaterialApp(
          home: AuthForgotPasswordScreen(
            onRequestReset: ({required email}) {
              return vm.requestPasswordReset(email: email);
            },
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField), 'user@example.com');
    await tester.pump();
    await tester.tap(find.text('Enviar código'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('ApiException'), findsNothing);
    expect(find.textContaining('Internal Server Error'), findsNothing);
    expect(
      find.text(
        'No pudimos completar la operación en este momento. '
        'Inténtalo nuevamente más tarde.',
      ),
      findsOneWidget,
    );
    expect(find.byType(AuthResetPasswordScreen), findsNothing);
  });

  testWidgets('reset password invalid token does not show JSON dump', (
    tester,
  ) async {
    final vm = viewModelWith(
      MockClient((request) async {
        return http.Response(
          jsonEncode({
            'detail': 'Invalid recovery code.',
            'code': 'recovery_code_invalid',
          }),
          400,
        );
      }),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewModel>.value(
        value: vm,
        child: MaterialApp(
          home: AuthResetPasswordScreen(
            email: 'user@example.com',
            onConfirmReset: ({required email, required code, required newPassword}) {
              return vm.confirmPasswordReset(
                email: email,
                code: code,
                newPassword: newPassword,
              );
            },
          ),
        ),
      ),
    );

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '000000');
    await tester.enterText(fields.at(1), 'newpass12');
    await tester.enterText(fields.at(2), 'newpass12');
    await tester.pump();
    await tester.tap(find.text('Guardar contraseña'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('ApiException'), findsNothing);
    expect(find.textContaining('recovery token'), findsNothing);
    expect(find.textContaining('Invalid recovery code'), findsNothing);
    expect(
      find.text(
        'El código de recuperación no es válido. Verifica el código enviado a tu correo.',
      ),
      findsOneWidget,
    );
  });
}
