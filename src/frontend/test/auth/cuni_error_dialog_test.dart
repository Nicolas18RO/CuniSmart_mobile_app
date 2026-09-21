import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/errors/auth_ui_error.dart';
import 'package:frontend/core/theme/cuni_theme.dart';
import 'package:frontend/features/auth/presentation/widgets/cuni_smart_error_dialog.dart';

void main() {
  const error = AuthUiError(
    kind: AuthUiKind.invalidCredentials,
    title: 'No se pudo iniciar sesión',
    message:
        'El correo o la contraseña son incorrectos. '
        'Verifica tus datos e inténtalo nuevamente.',
    action: 'Entendido',
    technicalCode: 'invalid_credentials',
  );

  testWidgets('showCuniSmartErrorDialog shows catalog copy without technical dump', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: CuniTheme.light(),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () => showCuniSmartErrorDialog(context, error),
                child: const Text('abrir'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('No se pudo iniciar sesión'), findsOneWidget);
    expect(
      find.text(
        'El correo o la contraseña son incorrectos. '
        'Verifica tus datos e inténtalo nuevamente.',
      ),
      findsOneWidget,
    );
    expect(find.text('Entendido'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.textContaining('ApiException'), findsNothing);
    expect(find.textContaining('invalid_credentials'), findsNothing);

    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('showCuniSmartErrorDialog exposes a TalkBack label with title and message', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: CuniTheme.light(),
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () => showCuniSmartErrorDialog(context, error),
                  child: const Text('abrir'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      final data = tester.getSemantics(find.byKey(const Key('cuniSmartErrorDialog')));
      expect(
        data.label,
        'No se pudo iniciar sesión. El correo o la contraseña son incorrectos. '
        'Verifica tus datos e inténtalo nuevamente.',
      );
    } finally {
      handle.dispose();
    }
  });
}
