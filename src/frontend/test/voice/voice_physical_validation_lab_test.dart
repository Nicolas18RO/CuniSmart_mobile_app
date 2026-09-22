import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/data/local/app_database.dart';
import 'package:frontend/services/rabbit_local_store.dart';
import 'package:frontend/services/rabbit_service.dart';
import 'package:frontend/services/sensor_service.dart';
import 'package:frontend/services/voice_command_parser.dart';
import 'package:frontend/viewmodels/rabbit_viewmodel.dart';
import 'package:frontend/viewmodels/sensor_viewmodel.dart';
import 'package:frontend/voice/controller/voice_controller.dart';
import 'package:frontend/voice/form/rabbit_create_voice_form_guidance.dart';
import 'package:frontend/voice/form/rabbit_create_voice_form_parser.dart';
import 'package:frontend/voice/form/rabbit_create_voice_form_snapshot.dart';
import 'package:frontend/voice/form/voice_form_field.dart';
import 'package:frontend/voice/form/voice_form_interaction_mapper.dart';
import 'package:frontend/voice/form/voice_form_interaction_state.dart';
import 'package:frontend/voice/hardware/hardware_voice_trigger.dart';

/// Lab de validación física (Gate PHYSICAL VALIDATION).
///
/// Simula el recorrido oral del alta guiada sin micrófono real.
/// Lo que requiere dispositivo (TTS audible, TalkBack, STT nativo) queda
/// documentado como POR VALIDAR en el informe del gate.
void main() {
  late VoiceController controller;

  setUp(() {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final rabbits = RabbitViewModel(
      RabbitService(
        ApiClient(httpClient: MockClient((_) async => http.Response('[]', 200))),
        RabbitLocalStore(db),
      ),
    );
    final sensors = SensorViewModel(
      SensorService(
        ApiClient(httpClient: MockClient((_) async => http.Response('[]', 200))),
      ),
    );
    controller = VoiceController(
      intentParser: VoiceIntentParser(const VoiceCommandParser()),
      aiEngine: VoiceAIEngine(rabbits, sensors),
    );
  });

  RabbitCreateVoiceFormSnapshot snap({
    required VoiceFormField field,
    bool nameEmpty = false,
    bool breedEmpty = false,
    bool birthDateEmpty = true,
    bool weightEmpty = true,
    bool notesEmpty = true,
  }) {
    return RabbitCreateVoiceFormSnapshot(
      routeOpen: true,
      nameEmpty: nameEmpty || field == VoiceFormField.name,
      breedEmpty: breedEmpty ||
          field == VoiceFormField.breed ||
          field == VoiceFormField.name,
      birthDateEmpty: birthDateEmpty,
      weightEmpty: weightEmpty,
      notesEmpty: notesEmpty,
      activeVoiceField: field,
    );
  }

  bool hasShellNav(VoiceOrchestrationResult plan) => plan.effects.any(
        (e) =>
            e.type == VoiceEffectType.popToRoot ||
            e.type == VoiceEffectType.changeTab ||
            e.type == VoiceEffectType.loadSensorReadings ||
            e.type == VoiceEffectType.startSensorPolling ||
            e.type == VoiceEffectType.openCreateRabbitScreen,
      );

  group('VE-PV lab golden path — voice create recovery', () {
    test('FSM maps birth date while form is open', () {
      final state = VoiceFormInteractionMapper.fromSnapshot(
        snap(field: VoiceFormField.birthDate),
      );
      expect(state, VoiceFormInteractionState.askingBirthDate);
    });

    test('VE-PV-01: "ver sensores" during birth date stays in form', () {
      final plan = controller.prepare(
        'ver sensores',
        shellTabIndex: 0,
        rabbitFormSnapshot: snap(field: VoiceFormField.birthDate),
      );
      expect(hasShellNav(plan), isFalse);
      expect(plan.speech!.toLowerCase(), contains('conejo'));
      expect(plan.shouldRestartListening, isTrue);
      expect(plan.speech!.toLowerCase(), anyOf(contains('fecha'), contains('cancelar')));
    });

    test('VE-PV-02: invalid date → format guidance + restart', () {
      final plan = controller.prepare(
        'bla bla fecha',
        shellTabIndex: 0,
        rabbitFormSnapshot: snap(field: VoiceFormField.birthDate),
      );
      expect(plan.rabbitCreateFormFills ?? const [], isEmpty);
      expect(plan.speech!.toLowerCase(), contains('fecha'));
      expect(plan.speech!.toLowerCase(), contains('ejemplo'));
      expect(plan.shouldRestartListening, isTrue);
    });

    test('VE-PV-03: valid digit date still fills birthDate', () {
      final fills = RabbitCreateVoiceFormParser.parseContinuation(
        '25 de septiembre de 2026',
        snap(field: VoiceFormField.birthDate, birthDateEmpty: true),
      );
      expect(fills, hasLength(1));
      expect(fills.single.value, '2026-09-25');
    });

    test('VE-PV-04: cancelar / repetir / ayuda on birth date', () {
      final cancel = controller.prepare(
        'cancelar',
        shellTabIndex: 0,
        rabbitFormSnapshot: snap(field: VoiceFormField.birthDate),
      );
      expect(hasShellNav(cancel), isFalse);
      expect(cancel.speech!.toLowerCase(), contains('cancelad'));
      expect(
        cancel.effects.any((e) => e.type == VoiceEffectType.cancelCreateRabbitForm),
        isTrue,
      );

      final repeat = controller.prepare(
        'repetir',
        shellTabIndex: 0,
        rabbitFormSnapshot: snap(field: VoiceFormField.birthDate),
      );
      expect(repeat.speech!.toLowerCase(), contains('fecha'));
      expect(repeat.shouldRestartListening, isTrue);

      final help = controller.prepare(
        'ayuda',
        shellTabIndex: 0,
        rabbitFormSnapshot: snap(field: VoiceFormField.birthDate),
      );
      expect(help.speech!.toLowerCase(), contains('ejemplo'));
      expect(help.shouldRestartListening, isTrue);
    });

    test('VE-PV-05: cancelar / repetir / ayuda also on sex and weight', () {
      for (final field in [VoiceFormField.sex, VoiceFormField.weight]) {
        final cancel = controller.prepare(
          'cancelar',
          shellTabIndex: 0,
          rabbitFormSnapshot: snap(field: field, birthDateEmpty: false),
        );
        expect(
          cancel.effects.any((e) => e.type == VoiceEffectType.cancelCreateRabbitForm),
          isTrue,
          reason: '$field cancel',
        );

        final help = controller.prepare(
          'ayuda',
          shellTabIndex: 0,
          rabbitFormSnapshot: snap(field: field, birthDateEmpty: false),
        );
        expect((help.speech ?? '').isNotEmpty, isTrue, reason: '$field help');
        expect(help.shouldRestartListening, isTrue);
      }
    });

    test('VE-PV-06: empty STT while form open is not silent', () {
      final plan = controller.prepare(
        '   ',
        shellTabIndex: 0,
        rabbitFormSnapshot: snap(field: VoiceFormField.birthDate),
      );
      expect(plan.speech!.trim().isNotEmpty, isTrue);
      expect(plan.shouldRestartListening, isTrue);
    });

    test('VE-PV-07: success copy never comes from prepare()', () {
      for (final phrase in ['ver sensores', 'confirmar', 'cancelar', 'ayuda']) {
        final plan = controller.prepare(
          phrase,
          shellTabIndex: 0,
          rabbitFormSnapshot: snap(field: VoiceFormField.birthDate),
        );
        expect(plan.speech ?? '', isNot(contains('Conejo creado')));
      }
    });

    test('VE-PV-08: confirmation prompts still teach confirmar/cancelar', () {
      final prompt = VoiceAIEngine.rabbitCreateFormConfirmationPrompt();
      expect(prompt.toLowerCase(), contains('confirmar'));
      expect(prompt.toLowerCase(), contains('cancelar'));
      expect(
        RabbitCreateVoiceFormGuidance.promptForField(VoiceFormField.birthDate)
            .toLowerCase(),
        contains('fecha'),
      );
    });

    test('VE-PV-09: hardware PoC remains Noop (no volume wiring)', () {
      final t = NoopHardwareVoiceTrigger();
      var fired = false;
      t.onTrigger = () => fired = true;
      t.start();
      t.stop();
      expect(fired, isFalse);
      expect(t, isA<HardwareVoiceTrigger>());
    });

    test('VE-PV-10: isolation holds for sex/weight/status globals', () {
      for (final field in [
        VoiceFormField.sex,
        VoiceFormField.weight,
        VoiceFormField.status,
      ]) {
        final plan = controller.prepare(
          'ver sensores',
          shellTabIndex: 0,
          rabbitFormSnapshot: snap(field: field, birthDateEmpty: false),
        );
        expect(hasShellNav(plan), isFalse, reason: '$field');
        expect(plan.shouldRestartListening, isTrue);
      }
    });
  });
}
