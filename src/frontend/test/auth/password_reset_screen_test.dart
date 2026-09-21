import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:frontend/features/auth/presentation/screens/login_screen.dart';
import 'package:frontend/features/auth/presentation/screens/reset_password_screen.dart';

void main() {
  testWidgets('login exposes forgot-password action', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AuthLoginScreen(onForgotPassword: () => opened = true),
      ),
    );
    await tester.tap(find.text('¿Olvidaste tu contraseña?'));
    await tester.pump();
    expect(opened, isTrue);
  });

  testWidgets('login can request verification resend', (tester) async {
    String? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: AuthLoginScreen(
          onResendVerification: ({required email}) async {
            captured = email;
          },
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField).first, 'user@example.com');
    await tester.pump();
    await tester.tap(find.text('Reenviar correo de verificación'));
    await tester.pumpAndSettle();
    expect(find.text('Verifica tu correo'), findsOneWidget);
    await tester.pump(const Duration(seconds: 60));
    await tester.pump();
    await tester.tap(find.text('Reenviar código'));
    await tester.pumpAndSettle();
    expect(captured, 'user@example.com');
  });

  testWidgets('forgot password submits email and opens reset screen', (
    tester,
  ) async {
    String? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: AuthForgotPasswordScreen(
          onRequestReset: ({required email}) async {
            captured = email;
          },
          onConfirmReset: ({required email, required code, required newPassword}) async {},
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField), 'user@example.com');
    await tester.pump();
    await tester.tap(find.text('Enviar código'));
    await tester.pumpAndSettle();
    expect(captured, 'user@example.com');
    expect(find.byType(AuthResetPasswordScreen), findsOneWidget);
  });

  testWidgets('reset password submits 6-digit code and new password', (tester) async {
    String? capturedEmail;
    String? capturedCode;
    String? capturedPassword;
    await tester.pumpWidget(
      MaterialApp(
        home: AuthResetPasswordScreen(
          email: 'user@example.com',
          onConfirmReset: ({required email, required code, required newPassword}) async {
            capturedEmail = email;
            capturedCode = code;
            capturedPassword = newPassword;
          },
        ),
      ),
    );

    expect(find.textContaining('user@example.com'), findsOneWidget);
    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Guardar contraseña'),
    );
    expect(save.onPressed, isNull);

    await tester.enterText(find.byKey(const Key('recoveryCodeField')), '482731');
    await tester.enterText(find.byType(TextFormField).at(1), 'newpass12');
    await tester.enterText(find.byType(TextFormField).at(2), 'newpass12');
    await tester.pump();
    await tester.tap(find.text('Guardar contraseña'));
    await tester.pump();
    expect(capturedEmail, 'user@example.com');
    expect(capturedCode, '482731');
    expect(capturedPassword, 'newpass12');
  });
}
