import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/voice/app_voice_form_bridge.dart';
import 'package:frontend/data/local/app_database.dart';
import 'package:frontend/services/rabbit_local_store.dart';
import 'package:frontend/services/rabbit_service.dart';
import 'package:frontend/services/sensor_service.dart';
import 'package:frontend/services/voice_command_parser.dart';
import 'package:frontend/viewmodels/rabbit_create_form_voice_controller.dart';
import 'package:frontend/viewmodels/rabbit_viewmodel.dart';
import 'package:frontend/viewmodels/sensor_viewmodel.dart';
import 'package:frontend/voice/controller/voice_controller.dart';
import 'package:frontend/voice/form/rabbit_create_voice_form_guidance.dart';
import 'package:frontend/voice/form/rabbit_create_voice_form_parser.dart';
import 'package:frontend/voice/form/rabbit_create_voice_form_snapshot.dart';
import 'package:frontend/voice/form/voice_form_field.dart';
import 'package:frontend/voice/form/voice_form_field_assignment.dart';
import 'package:frontend/voice/hardware/volume_up_long_press_voice_trigger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VoiceController controller;

  setUp(() {
    RabbitCreateVoiceFormParser.debugTodayOverride = DateTime(2026, 9, 21);
    final db = AppDatabase.memory();
    addTearDown(db.close);
    controller = VoiceController(
      intentParser: VoiceIntentParser(const VoiceCommandParser()),
      aiEngine: VoiceAIEngine(
        RabbitViewModel(
          RabbitService(
            ApiClient(
              httpClient: MockClient((_) async => http.Response('[]', 200)),
            ),
            RabbitLocalStore(db),
          ),
        ),
        SensorViewModel(
          SensorService(
            ApiClient(
              httpClient: MockClient((_) async => http.Response('[]', 200)),
            ),
          ),
        ),
      ),
    );
  });

  tearDown(() {
    RabbitCreateVoiceFormParser.debugTodayOverride = null;
  });

  RabbitCreateVoiceFormSnapshot confirmingSnap() =>
      const RabbitCreateVoiceFormSnapshot(
        routeOpen: true,
        nameEmpty: false,
        breedEmpty: false,
        birthDateEmpty: false,
        weightEmpty: false,
        notesEmpty: false,
        activeVoiceField: null,
      );

  RabbitCreateVoiceFormSnapshot birthSnap() =>
      const RabbitCreateVoiceFormSnapshot(
        routeOpen: true,
        nameEmpty: false,
        breedEmpty: false,
        birthDateEmpty: true,
        weightEmpty: true,
        notesEmpty: true,
        activeVoiceField: VoiceFormField.birthDate,
      );

  group('A — correction intents from confirming snapshot', () {
    test('A1–A10 field targets', () {
      final cases = <String, VoiceFormField>{
        'corregir nombre': VoiceFormField.name,
        'corregir raza': VoiceFormField.breed,
        'corregir sexo': VoiceFormField.sex,
        'corregir fecha': VoiceFormField.birthDate,
        'corregir fecha de nacimiento': VoiceFormField.birthDate,
        'corregir peso': VoiceFormField.weight,
        'corregir estado': VoiceFormField.status,
        'corregir notas': VoiceFormField.notes,
        'cambiar peso': VoiceFormField.weight,
        'modificar peso': VoiceFormField.weight,
      };
      for (final e in cases.entries) {
        final plan = controller.prepare(
          e.key,
          shellTabIndex: 0,
          rabbitFormSnapshot: confirmingSnap(),
        );
        expect(plan.correctFormField, e.value, reason: e.key);
        expect(plan.speech!.toLowerCase(), contains('corregir'));
        expect(plan.shouldRestartListening, isTrue);
        expect(plan.speech ?? '', isNot(contains('Conejo creado')));
      }
    });

    test('A11–A15 correction from CONFIRMING is local-only then re-arms', () {
      final bridge = AppVoiceFormBridge();
      final form = RabbitCreateFormVoiceController();
      bridge.registerRabbitCreate(form);

      form.name.text = 'Copito';
      form.breed.text = 'Rex';
      form.setSex('male');
      form.setBirthDateText('2026-07-15');
      form.applyAssignments(const [
        VoiceFormFieldAssignment(VoiceFormField.weight, '2.5'),
        VoiceFormFieldAssignment(VoiceFormField.status, 'active'),
        VoiceFormFieldAssignment(VoiceFormField.notes, ''),
      ]);
      expect(form.readyForFinalVoiceConfirmation, isTrue);

      final armedSpeech = bridge.takeFinalReviewAndArmIfReady();
      expect(armedSpeech, isNotNull);
      expect(bridge.isAwaitingFinalConfirmation, isTrue);

      // Mismo camino que VoiceViewModel._handleRabbitCreateFinalVoice (antes de sí/cancelar).
      final plan = controller.prepare(
        'corregir peso',
        shellTabIndex: 0,
        rabbitFormSnapshot: bridge.readRabbitCreateSnapshot(),
      );
      expect(plan.correctFormField, VoiceFormField.weight);
      expect(plan.speech ?? '', isNot(contains('Conejo creado')));

      bridge.beginVoiceCorrection(plan.correctFormField!);
      expect(bridge.isAwaitingFinalConfirmation, isFalse);
      expect(form.activeVoiceField, VoiceFormField.weight);
      expect(form.weight.text, isEmpty);

      final guidance = bridge.applyRabbitCreateAssignmentsWithGuidance(const [
        VoiceFormFieldAssignment(VoiceFormField.weight, '3'),
      ]);
      expect(form.weight.text, '3');
      expect(form.weight.text, isNot('2.5'));
      expect(guidance, isNotNull);
      expect(bridge.isAwaitingFinalConfirmation, isTrue);
    });
  });

  group('B — relative dates', () {
    test('B1 absolute still works', () {
      final fills = RabbitCreateVoiceFormParser.parseContinuation(
        '25 de septiembre de 2026',
        birthSnap(),
      );
      expect(fills.single.value, '2026-09-25');
    });

    test('B2 spoken numerals', () {
      final fills = RabbitCreateVoiceFormParser.parseContinuation(
        'veinticinco de septiembre de dos mil veintiséis',
        birthSnap(),
      );
      expect(fills.single.value, '2026-09-25');
    });

    test('B3 del 2026', () {
      final fills = RabbitCreateVoiceFormParser.parseContinuation(
        'veinticinco de septiembre del 2026',
        birthSnap(),
      );
      expect(fills.single.value, '2026-09-25');
    });

    test('B4 hoy', () {
      final fills = RabbitCreateVoiceFormParser.parseContinuation(
        'hoy',
        birthSnap(),
      );
      expect(fills.single.value, '2026-09-21');
    });

    test('B5 ayer', () {
      final fills = RabbitCreateVoiceFormParser.parseContinuation(
        'ayer',
        birthSnap(),
      );
      expect(fills.single.value, '2026-09-20');
    });

    test('B6 antier', () {
      final fills = RabbitCreateVoiceFormParser.parseContinuation(
        'antier',
        birthSnap(),
      );
      expect(fills.single.value, '2026-09-19');
    });

    test('B9 month/year rollover', () {
      RabbitCreateVoiceFormParser.debugTodayOverride = DateTime(2026, 1, 1);
      expect(
        RabbitCreateVoiceFormParser.parseContinuation('ayer', birthSnap())
            .single
            .value,
        '2025-12-31',
      );
      expect(
        RabbitCreateVoiceFormParser.parseContinuation('antier', birthSnap())
            .single
            .value,
        '2025-12-30',
      );
    });
  });

  group('C — natural TTS date guidance', () {
    test('C1–C4 natural example without ISO', () {
      final help = RabbitCreateVoiceFormGuidance.helpForField(
        VoiceFormField.birthDate,
      );
      final err = RabbitCreateVoiceFormGuidance.unrecognizedBirthDate();
      expect(help, contains('15 de julio de 2026'));
      expect(help.toLowerCase(), isNot(contains('2026-07-15')));
      expect(help.toLowerCase(), isNot(contains('guion')));
      expect(err, contains('15 de julio de 2026'));
      expect(err.toLowerCase(), anyOf(contains('hoy'), contains('ayer')));
    });
  });

  group('D — Volume Up trigger', () {
    test('D1–D3 long Up fires; short does not', () {
      var fired = 0;
      var clock = DateTime.utc(2026, 1, 1);
      final t = VolumeUpLongPressVoiceTrigger(
        attachHardwareKeyboard: false,
        now: () => clock,
      );
      t.onTrigger = () => fired++;
      t.start();
      t.handleVolumeUpDown();
      clock = clock.add(const Duration(milliseconds: 200));
      t.tick();
      t.handleVolumeUpUp();
      expect(fired, 0);
      t.handleVolumeUpDown();
      clock = clock.add(const Duration(milliseconds: 800));
      t.tick();
      expect(fired, 1);
      expect(t.volumeKey, LogicalKeyboardKey.audioVolumeUp);
    });
  });
}
