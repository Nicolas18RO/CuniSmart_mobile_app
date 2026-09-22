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
import 'package:frontend/voice/form/rabbit_create_voice_form_parser.dart';
import 'package:frontend/voice/form/rabbit_create_voice_form_snapshot.dart';
import 'package:frontend/voice/form/voice_form_field.dart';
import 'package:frontend/voice/hardware/volume_up_long_press_voice_trigger.dart';

/// VOICE INTERACTION ENHANCEMENT — weight / correction / hardware contracts.
void main() {
  late VoiceController controller;

  setUp(() {
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

  RabbitCreateVoiceFormSnapshot weightSnap() => const RabbitCreateVoiceFormSnapshot(
        routeOpen: true,
        nameEmpty: false,
        breedEmpty: false,
        birthDateEmpty: false,
        weightEmpty: true,
        notesEmpty: true,
        activeVoiceField: VoiceFormField.weight,
      );

  RabbitCreateVoiceFormSnapshot nameSnap() => const RabbitCreateVoiceFormSnapshot(
        routeOpen: true,
        nameEmpty: true,
        breedEmpty: true,
        birthDateEmpty: true,
        weightEmpty: true,
        notesEmpty: true,
        activeVoiceField: VoiceFormField.name,
      );

  String? weightValue(String phrase) {
    final fills = RabbitCreateVoiceFormParser.parseContinuation(
      phrase,
      weightSnap(),
    );
    if (fills.isEmpty) return null;
    return fills.single.value;
  }

  group('WEIGHT semantic kg parsing', () {
    test('WEIGHT-01 "15"', () => expect(weightValue('15'), '15'));
    test('WEIGHT-02 "15 kilos"', () => expect(weightValue('15 kilos'), '15'));
    test('WEIGHT-03 "15 kilogramos"',
        () => expect(weightValue('15 kilogramos'), '15'));
    test('WEIGHT-04 "15 kg"', () => expect(weightValue('15 kg'), '15'));
    test('WEIGHT-05 "15.5 kilos"',
        () => expect(weightValue('15.5 kilos'), '15.5'));
    test('WEIGHT-06 "15,5 kilos"',
        () => expect(weightValue('15,5 kilos'), '15.5'));
    test('WEIGHT-07 "dos kilos"', () => expect(weightValue('dos kilos'), '2'));
    test('WEIGHT-07b "dos punto cinco kilos"',
        () => expect(weightValue('dos punto cinco kilos'), '2.5'));
    test('WEIGHT-07c "peso 15 kilos"',
        () => expect(weightValue('peso 15 kilos'), '15'));
    test('WEIGHT-08 invalid', () {
      expect(weightValue('bla bla'), isNull);
      expect(weightValue('15 gramos'), isNull);
    });
  });

  group('CORRECTION interactive field jump', () {
    test('CORRECTION-01 corregir nombre', () {
      final plan = controller.prepare(
        'corregir nombre',
        shellTabIndex: 0,
        rabbitFormSnapshot: weightSnap(),
      );
      expect(plan.correctFormField, VoiceFormField.name);
      expect(plan.speech!.toLowerCase(), contains('nombre'));
      expect(plan.shouldRestartListening, isTrue);
      expect(plan.rabbitCreateFormFills, isNull);
    });

    test('CORRECTION-02..07 field targets', () {
      expect(
        controller
            .prepare('corregir raza',
                shellTabIndex: 0, rabbitFormSnapshot: weightSnap())
            .correctFormField,
        VoiceFormField.breed,
      );
      expect(
        controller
            .prepare('corregir sexo',
                shellTabIndex: 0, rabbitFormSnapshot: weightSnap())
            .correctFormField,
        VoiceFormField.sex,
      );
      expect(
        controller
            .prepare('corregir fecha de nacimiento',
                shellTabIndex: 0, rabbitFormSnapshot: weightSnap())
            .correctFormField,
        VoiceFormField.birthDate,
      );
      expect(
        controller
            .prepare('cambiar peso',
                shellTabIndex: 0, rabbitFormSnapshot: nameSnap())
            .correctFormField,
        VoiceFormField.weight,
      );
      expect(
        controller
            .prepare('modificar estado',
                shellTabIndex: 0, rabbitFormSnapshot: weightSnap())
            .correctFormField,
        VoiceFormField.status,
      );
      expect(
        controller
            .prepare('corregir notas',
                shellTabIndex: 0, rabbitFormSnapshot: weightSnap())
            .correctFormField,
        VoiceFormField.notes,
      );
    });

    test('CORRECTION-08 while name active does not fill name', () {
      final plan = controller.prepare(
        'corregir raza',
        shellTabIndex: 0,
        rabbitFormSnapshot: nameSnap(),
      );
      expect(plan.correctFormField, VoiceFormField.breed);
      expect(plan.rabbitCreateFormFills, isNull);
    });

    test('CORRECTION-09 no shell create / no Conejo creado', () {
      final plan = controller.prepare(
        'corregir peso',
        shellTabIndex: 0,
        rabbitFormSnapshot: nameSnap(),
      );
      expect(
        plan.effects.any((e) => e.type == VoiceEffectType.openCreateRabbitScreen),
        isFalse,
      );
      expect(plan.speech ?? '', isNot(contains('Conejo creado')));
    });
  });

  group('HARDWARE activation contracts', () {
    test('HARDWARE-01/02/05 long vs short', () {
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
    });

    test('HARDWARE-03 combo NOT implemented (LIMITATION)', () {
      // Documented: volume up+down combo is not wired.
      expect(true, isTrue);
    });

    test('HARDWARE-04 POWER NOT implemented (LIMITATION)', () {
      // Android restricts POWER; not captured by VolumeUpLongPressVoiceTrigger.
      expect(true, isTrue);
    });
  });
}
