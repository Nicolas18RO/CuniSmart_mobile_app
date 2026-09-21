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

/// G9.1 — contrato del diálogo previo a activar biometría (TDD).
///
/// Copy honesta: describe el candado al abrir la app, no un login
/// biométrico después de cerrar sesión (ese flujo no existe).
void main() {
  const title = 'Activar autenticación biométrica';
  const message =
      'Al activar esta opción, al abrir la aplicación se te pedirá tu huella '
      'o el método biométrico configurado en tu dispositivo.';

  Future<
      ({
        AuthViewModel vm,
        FakeDeviceAuthenticator device,
        List<http.Request> puts,
      })> pumpSettings(
    WidgetTester tester, {
    bool flagAlreadyEnabled = false,
  }) async {
    final puts = <http.Request>[];
    final device = FakeDeviceAuthenticator(
      available: true,
      outcome: FakeBiometricAuthOutcome.success,
    );
    final api = ApiClient(
      httpClient: MockClient((request) async {
        if (request.method == 'PUT') {
          puts.add(request);
          return http.Response(
            request.body,
            200,
          );
        }
        return http.Response(
          jsonEncode({'biometric_enabled': flagAlreadyEnabled}),
          200,
        );
      }),
      baseUrl: 'http://example.test',
    );
    final vm = AuthViewModel(
      authService: AuthService(
        apiClient: api,
        tokenStorage: AuthTokenStorage.inMemory(),
      ),
      deviceAuth: device,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewModel>.value(
        value: vm,
        child: const MaterialApp(home: AuthSecuritySettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return (vm: vm, device: device, puts: puts);
  }

  Future<void> tapEnableSwitch(WidgetTester tester) async {
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
  }

  group('G9.1 activation dialog', () {
    testWidgets('enabling shows explanation before the system prompt',
        (tester) async {
      final h = await pumpSettings(tester);

      await tapEnableSwitch(tester);

      expect(find.text(title), findsOneWidget);
      expect(find.text(message), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.text('Continuar'), findsOneWidget);
      expect(h.device.authenticateCalls, 0);
      expect(h.puts, isEmpty);
      expect(h.vm.biometricEnabled, isFalse);
    });

    testWidgets('Cancelar does not prompt, PUT, or enable the flag',
        (tester) async {
      final h = await pumpSettings(tester);

      await tapEnableSwitch(tester);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.text(title), findsNothing);
      expect(h.device.authenticateCalls, 0);
      expect(h.puts, isEmpty);
      expect(h.vm.biometricEnabled, isFalse);
      final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(tile.value, isFalse);
    });

    testWidgets('Continuar then requests biometrics and PUTs the flag',
        (tester) async {
      final h = await pumpSettings(tester);

      await tapEnableSwitch(tester);
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();

      expect(find.text(title), findsNothing);
      expect(h.device.authenticateCalls, 1);
      expect(h.puts, hasLength(1));
      expect(jsonDecode(h.puts.single.body), {'biometric_enabled': true});
      expect(h.vm.biometricEnabled, isTrue);
    });

    testWidgets('TalkBack can read title, message and both actions',
        (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await pumpSettings(tester);
        await tapEnableSwitch(tester);

        final dialog = tester.getSemantics(
          find.byKey(const Key('biometricActivationDialog')),
        );
        expect(dialog.label, '$title. $message');

        expect(
          tester.getSemantics(find.text('Cancelar')),
          containsSemantics(label: 'Cancelar', isButton: true),
        );
        expect(
          tester.getSemantics(find.text('Continuar')),
          containsSemantics(label: 'Continuar', isButton: true),
        );
      } finally {
        handle.dispose();
      }
    });

    testWidgets('turning the switch off does not show the activation dialog',
        (tester) async {
      final h = await pumpSettings(tester, flagAlreadyEnabled: true);

      await tapEnableSwitch(tester);

      expect(find.text(title), findsNothing);
      expect(h.device.authenticateCalls, 0);
      expect(h.puts, hasLength(1));
      expect(jsonDecode(h.puts.single.body), {'biometric_enabled': false});
      expect(h.vm.biometricEnabled, isFalse);
    });
  });
}
