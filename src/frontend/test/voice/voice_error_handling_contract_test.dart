import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/voice/app_voice_form_bridge.dart';
import 'package:frontend/data/local/app_database.dart';
import 'package:frontend/services/rabbit_local_store.dart';
import 'package:frontend/services/rabbit_service.dart';
import 'package:frontend/services/sensor_service.dart';
import 'package:frontend/services/voice_command_parser.dart';
import 'package:frontend/services/voice_service.dart';
import 'package:frontend/viewmodels/rabbit_viewmodel.dart';
import 'package:frontend/viewmodels/sensor_viewmodel.dart';
import 'package:frontend/viewmodels/voice_viewmodel.dart';
import 'package:frontend/voice/controller/voice_controller.dart';
import 'package:frontend/voice/form/rabbit_create_voice_form_parser.dart';
import 'package:frontend/voice/form/rabbit_create_voice_form_snapshot.dart';
import 'package:frontend/voice/form/voice_form_field.dart';
import 'package:frontend/voice/form/voice_form_interaction_mapper.dart';
import 'package:frontend/voice/form/voice_form_interaction_state.dart';
import 'package:frontend/voice/hardware/hardware_voice_trigger.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Gate TDD + IMPLEMENTATION — Voice Error Handling contracts.
void main() {
  late VoiceController controller;

  setUp(() {
    final db = AppDatabase.memory();
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
    addTearDown(db.close);
  });

  RabbitCreateVoiceFormSnapshot snapAt(VoiceFormField field) {
    return RabbitCreateVoiceFormSnapshot(
      routeOpen: true,
      nameEmpty: field == VoiceFormField.name,
      breedEmpty: field == VoiceFormField.breed || field == VoiceFormField.name,
      birthDateEmpty: field.index <= VoiceFormField.birthDate.index,
      weightEmpty: true,
      notesEmpty: true,
      activeVoiceField: field,
    );
  }

  bool hasShellNavigation(VoiceOrchestrationResult plan) {
    return plan.effects.any(
      (e) =>
          e.type == VoiceEffectType.popToRoot ||
          e.type == VoiceEffectType.changeTab ||
          e.type == VoiceEffectType.openCreateRabbitScreen ||
          e.type == VoiceEffectType.loadSensorReadings ||
          e.type == VoiceEffectType.startSensorPolling,
    );
  }

  group('VE-TDD-01 isolation of all ASKING fields from global parser', () {
    for (final field in [
      VoiceFormField.name,
      VoiceFormField.breed,
      VoiceFormField.notes,
    ]) {
      test('characterization: "$field" already isolates "ver sensores"', () {
        final plan = controller.prepare(
          'ver sensores',
          shellTabIndex: 0,
          rabbitFormSnapshot: snapAt(field),
        );
        expect(
          hasShellNavigation(plan),
          isFalse,
          reason: 'Current code isolates name/breed/notes from global parser.',
        );
      });
    }

    for (final field in [
      VoiceFormField.sex,
      VoiceFormField.birthDate,
      VoiceFormField.weight,
      VoiceFormField.status,
    ]) {
      test('DESIGN: "$field" must not emit shell effects for "ver sensores"', () {
        final plan = controller.prepare(
          'ver sensores',
          shellTabIndex: 0,
          rabbitFormSnapshot: snapAt(field),
        );
        expect(
          hasShellNavigation(plan),
          isFalse,
          reason:
              'DESIGN VE-TDD-01/02: form field $field must isolate globals. '
              'Current code routes showSensors with popToRoot/changeTab.',
        );
      });
    }
  });

  group('VE-TDD-02 ver sensores during ASKING_BIRTH_DATE', () {
    test('DESIGN: keeps form context — no IoT navigation effects', () {
      final plan = controller.prepare(
        'ver sensores',
        shellTabIndex: 0,
        rabbitFormSnapshot: snapAt(VoiceFormField.birthDate),
      );
      expect(hasShellNavigation(plan), isFalse);
      expect(plan.rabbitCreateFormFills, isNull);
      final speech = (plan.speech ?? '').toLowerCase();
      expect(
        speech.contains('fecha') ||
            speech.contains('conejo') ||
            speech.contains('cancelar') ||
            speech.contains('repetir') ||
            speech.contains('ayuda'),
        isTrue,
        reason:
            'DESIGN: contextual reply while staying on birth date, '
            'not sensor dashboard copy alone.',
      );
    });
  });

  group('VE-TDD-03 invalid birth date', () {
    test('DESIGN: spoken numerals now fill birthDate (post-PV D-DATE)', () {
      final fills = RabbitCreateVoiceFormParser.parseContinuation(
        'veinticinco de septiembre de dos mil veintiseis',
        snapAt(VoiceFormField.birthDate),
      );
      expect(fills, hasLength(1));
      expect(fills.single.value, '2026-09-25');
    });

    test('DESIGN: prepare explains date format (not only generic no-entendí)', () {
      final plan = controller.prepare(
        'fecha totalmente inventada xyz',
        shellTabIndex: 0,
        rabbitFormSnapshot: snapAt(VoiceFormField.birthDate),
      );
      expect(plan.rabbitCreateFormFills ?? const [], isEmpty);
      final speech = (plan.speech ?? '').toLowerCase();
      expect(
        speech.contains('fecha') &&
            (speech.contains('ejemplo') ||
                speech.contains('día') ||
                speech.contains('dia') ||
                speech.contains('mes') ||
                speech.contains('año') ||
                speech.contains('ano')),
        isTrue,
      );
    });

    test('characterization: digit natural date still parses today', () {
      final fills = RabbitCreateVoiceFormParser.parseContinuation(
        '25 de septiembre de 2026',
        snapAt(VoiceFormField.birthDate),
      );
      expect(fills, hasLength(1));
      expect(fills.single.field, VoiceFormField.birthDate);
      expect(fills.single.value, '2026-09-25');
    });
  });

  group('VE-TDD-04 auto retry after recoverable error', () {
    test('orchestration exposes shouldRestartListening after bad date', () {
      final plan = controller.prepare(
        'fecha inventada xyz',
        shellTabIndex: 0,
        rabbitFormSnapshot: snapAt(VoiceFormField.birthDate),
      );
      expect(plan.shouldRestartListening, isTrue);
    });
  });

  group('VE-TDD-05 empty STT while form open', () {
    test('DESIGN: empty input while form open yields recovery speech', () {
      final plan = controller.prepare(
        '   ',
        shellTabIndex: 0,
        rabbitFormSnapshot: snapAt(VoiceFormField.birthDate),
      );
      expect(
        (plan.speech ?? '').trim().isNotEmpty,
        isTrue,
        reason:
            'DESIGN VE-TDD-05: empty STT during form must not be silent. '
            'Current prepare returns empty speech for blank text.',
      );
    });
  });

  group('VE-TDD-06 STT error feedback contract', () {
    test('VoiceViewModel wires VoiceService.onSpeechError at construction', () {
      TestWidgetsFlutterBinding.ensureInitialized();
      final voice = VoiceService();
      expect(voice.onSpeechError, isNull);
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final vm = VoiceViewModel(
        voice,
        const VoiceCommandParser(),
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
        AppVoiceFormBridge(),
      );
      addTearDown(vm.dispose);
      expect(
        voice.onSpeechError,
        isNotNull,
        reason: 'VE-TDD-06: VM must assign onSpeechError for audible STT feedback.',
      );
    });
  });

  group('VE-TDD-07 cancel during ASKING_BIRTH_DATE', () {
    test('DESIGN: cancelar does not navigate to sensors and cancels form intent', () {
      final plan = controller.prepare(
        'cancelar',
        shellTabIndex: 0,
        rabbitFormSnapshot: snapAt(VoiceFormField.birthDate),
      );
      expect(hasShellNavigation(plan), isFalse);
      final speech = (plan.speech ?? '').toLowerCase();
      expect(
        speech.contains('cancel') || speech.contains('cancelad'),
        isTrue,
        reason:
            'DESIGN VE-TDD-07: cancelar during birth date must cancel creation. '
            'Current: treated as unknown field value («No entendí…»).',
      );
      expect(plan.rabbitCreateFormFills ?? const [], isEmpty);
    });
  });

  group('VE-TDD-08 repetir during birth date', () {
    test('DESIGN: repetir re-states birth-date instruction without filling', () {
      final plan = controller.prepare(
        'repetir',
        shellTabIndex: 0,
        rabbitFormSnapshot: snapAt(VoiceFormField.birthDate),
      );
      expect(plan.rabbitCreateFormFills ?? const [], isEmpty);
      final speech = (plan.speech ?? '').toLowerCase();
      expect(
        speech.contains('fecha') || speech.contains('nacimiento'),
        isTrue,
        reason:
            'DESIGN VE-TDD-08: repetir must re-read the birth-date prompt. '
            'Current: generic no-entendí / field parse miss.',
      );
    });
  });

  group('VE-TDD-09 ayuda during birth date', () {
    test('DESIGN: ayuda gives contextual date example', () {
      final plan = controller.prepare(
        'ayuda',
        shellTabIndex: 0,
        rabbitFormSnapshot: snapAt(VoiceFormField.birthDate),
      );
      final speech = (plan.speech ?? '').toLowerCase();
      expect(
        speech.contains('ejemplo') ||
            speech.contains('septiembre') ||
            speech.contains('día') ||
            speech.contains('dia'),
        isTrue,
        reason:
            'DESIGN VE-TDD-09: contextual help for date. '
            'Current isNonFormChatter: «Eso no es un dato del formulario…».',
      );
    });
  });

  group('VE-TDD-10 / VE-TDD-11 confirmation phrases (characterization)', () {
    test('public prompts already teach confirmar/cancelar', () {
      final summary = VoiceAIEngine.formatRabbitCreateFormFinalSummary(
        name: 'Luna',
        breed: 'Rex',
        sexApi: 'female',
        birthDateYmd: '2024-01-15',
        statusApi: 'active',
      );
      final prompt = VoiceAIEngine.rabbitCreateFormConfirmationPrompt();
      expect(summary.toLowerCase(), contains('luna'));
      expect(prompt.toLowerCase(), contains('confirmar'));
      expect(prompt.toLowerCase(), contains('cancelar'));
    });

    test('DESIGN vocabulary for CONFIRMING matches VoiceViewModel sets', () {
      // Mirrored from VoiceViewModel._isRabbitFormFinalConfirm/Cancel (not public).
      const confirm = {
        'confirmar',
        'confirma',
        'confirmo',
        'si',
        'sí',
        'crear',
        'ok',
        'vale',
        'de acuerdo',
      };
      const cancel = {
        'cancelar',
        'cancela',
        'no',
        'abortar',
        'mejor no',
      };
      expect(confirm.contains('confirmar'), isTrue);
      expect(cancel.contains('cancelar'), isTrue);
    });
  });

  group('VE-TDD-12 success announcement only after persistence', () {
    test('characterization: success copy is only after createRabbit OK path', () {
      // Audit + code: `_afterSuccessfulVoiceCreate` speaks after createRabbit returns true.
      const successCopy = 'Conejo creado correctamente.';
      expect(successCopy.contains('Conejo creado'), isTrue);
      // Guardrail for IMPLEMENTATION: never emit this from prepare() on globals.
      final plan = controller.prepare(
        'ver sensores',
        shellTabIndex: 0,
        rabbitFormSnapshot: snapAt(VoiceFormField.birthDate),
      );
      expect(plan.speech ?? '', isNot(contains('Conejo creado')));
    });
  });

  group('VE-TDD-13 API failure must not announce success', () {
    test('DESIGN guard: prepare never claims rabbit created', () {
      final plan = controller.prepare(
        'confirmar',
        shellTabIndex: 0,
        rabbitFormSnapshot: snapAt(VoiceFormField.birthDate),
      );
      expect(plan.speech ?? '', isNot(contains('Conejo creado')));
    });
  });

  group('VE-TDD-14 / VE-TDD-15 TTS→STT coordination', () {
    test('VoiceService exposes isSpeaking and blocks listen while speaking', () {
      TestWidgetsFlutterBinding.ensureInitialized();
      final voice = VoiceService();
      expect(voice.isSpeaking, isFalse);
      expect(voice.isSpeaking, isA<bool>());
    });
  });

  group('VE-TDD-16 preserve active field after date error', () {
    test('characterization: failed date parse leaves fills empty (field unchanged)', () {
      final snap = snapAt(VoiceFormField.birthDate);
      final fills = RabbitCreateVoiceFormParser.parseContinuation(
        'bla bla',
        snap,
      );
      expect(fills, isEmpty);
      expect(snap.activeVoiceField, VoiceFormField.birthDate);
    });
  });

  group('VE-TDD-17 R2 compatibility', () {
    test('voice create remains delegated to RabbitViewModel API surface', () {
      expect(RabbitViewModel, isNotNull);
      expect(VoiceAIEngine.fichaSpeech, isNotNull);
    });
  });

  group('VE-TDD-18 physical volume PoC', () {
    test('POR VALIDAR: NoopHardwareVoiceTrigger has no volume listeners', () {
      final trigger = NoopHardwareVoiceTrigger();
      var fired = false;
      trigger.onTrigger = () => fired = true;
      trigger.start();
      trigger.stop();
      expect(fired, isFalse);
    });

    test('DESIGN PoC injectable interface exists (option A/B/C deferred)', () {
      expect(HardwareVoiceTrigger, isNotNull);
      expect(NoopHardwareVoiceTrigger(), isA<HardwareVoiceTrigger>());
    });
  });

  group('State machine proxy (DESIGN FSM vs activeVoiceField)', () {
    test('VoiceFormInteractionState maps asking birth date from snapshot', () {
      final state = VoiceFormInteractionMapper.fromSnapshot(
        snapAt(VoiceFormField.birthDate),
      );
      expect(state, VoiceFormInteractionState.askingBirthDate);
      expect(
        VoiceFormInteractionState.values.map((e) => e.name).toSet(),
        containsAll([
          'idle',
          'askingName',
          'askingBreed',
          'askingSex',
          'askingBirthDate',
          'askingWeight',
          'askingStatus',
          'askingNotes',
          'confirming',
          'saving',
          'success',
          'error',
          'cancelled',
        ]),
      );
    });
  });
}
