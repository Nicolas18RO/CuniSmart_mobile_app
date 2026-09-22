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

/// Gate TDD post-PV — fechas en letras (DESIGN D-DATE). Rojo esperado hasta IMPLEMENTATION.
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

  RabbitCreateVoiceFormSnapshot birthSnap() => const RabbitCreateVoiceFormSnapshot(
        routeOpen: true,
        nameEmpty: false,
        breedEmpty: false,
        birthDateEmpty: true,
        weightEmpty: true,
        notesEmpty: true,
        activeVoiceField: VoiceFormField.birthDate,
      );

  /// Ejemplo natural TTS + forma hablada larga (parser).
  const spokenCanonical =
      'veinticinco de septiembre de dos mil veintiséis';
  const naturalExample = '15 de julio de 2026';

  group('VE-DATE-01 spoken numerals → ISO', () {
    test('veinticinco… dos mil veintiséis → 2026-09-25', () {
      final fills = RabbitCreateVoiceFormParser.parseContinuation(
        spokenCanonical,
        birthSnap(),
      );
      expect(fills, hasLength(1));
      expect(fills.single.field, VoiceFormField.birthDate);
      expect(fills.single.value, '2026-09-25');
    });

    test('also accepts without accent on veintiseis', () {
      final fills = RabbitCreateVoiceFormParser.parseContinuation(
        'veinticinco de septiembre de dos mil veintiseis',
        birthSnap(),
      );
      expect(fills.single.value, '2026-09-25');
    });
  });

  group('VE-DATE-02 TTS canonical example must parse', () {
    test('helpForField uses natural example and spoken still parses', () {
      final help = RabbitCreateVoiceFormGuidance.helpForField(
        VoiceFormField.birthDate,
      );
      expect(help, contains(naturalExample));
      expect(help.toLowerCase(), isNot(contains('2026-07-15')));
      expect(help.toLowerCase(), anyOf(contains('hoy'), contains('ayer')));

      final fills = RabbitCreateVoiceFormParser.parseContinuation(
        spokenCanonical,
        birthSnap(),
      );
      expect(fills.single.value, '2026-09-25');
      expect(
        RabbitCreateVoiceFormParser.parseContinuation(
          naturalExample,
          birthSnap(),
        ).single.value,
        '2026-07-15',
      );
    });

    test('unrecognizedBirthDate copy matches natural example', () {
      final msg = RabbitCreateVoiceFormGuidance.unrecognizedBirthDate();
      expect(msg, contains(naturalExample));
      expect(msg.toLowerCase(), anyOf(contains('hoy'), contains('ayer')));
    });
  });

  group('VE-DATE-03 digit formats remain OK (regression)', () {
    test('25 de septiembre de 2026', () {
      final fills = RabbitCreateVoiceFormParser.parseContinuation(
        '25 de septiembre de 2026',
        birthSnap(),
      );
      expect(fills.single.value, '2026-09-25');
    });

    test('2026-09-25 and 25/09/2026', () {
      expect(
        RabbitCreateVoiceFormParser.parseContinuation(
          '2026-09-25',
          birthSnap(),
        ).single.value,
        '2026-09-25',
      );
      expect(
        RabbitCreateVoiceFormParser.parseContinuation(
          '25/09/2026',
          birthSnap(),
        ).single.value,
        '2026-09-25',
      );
    });
  });

  group('VE-DATE-04 tolerate del', () {
    test('25 de septiembre del 2026', () {
      final fills = RabbitCreateVoiceFormParser.parseContinuation(
        '25 de septiembre del 2026',
        birthSnap(),
      );
      expect(fills.single.value, '2026-09-25');
    });

    test('veinticinco de septiembre del dos mil veintiséis', () {
      final fills = RabbitCreateVoiceFormParser.parseContinuation(
        'veinticinco de septiembre del dos mil veintiséis',
        birthSnap(),
      );
      expect(fills.single.value, '2026-09-25');
    });
  });

  group('VE-DATE-05 garbage still recovers with canonical help', () {
    test('prepare: no fill, restart, speech cites natural example', () {
      final plan = controller.prepare(
        'fecha inventada xyz',
        shellTabIndex: 0,
        rabbitFormSnapshot: birthSnap(),
      );
      expect(plan.rabbitCreateFormFills ?? const [], isEmpty);
      expect(plan.shouldRestartListening, isTrue);
      expect(plan.speech ?? '', contains(naturalExample));
      expect((plan.speech ?? '').toLowerCase(), isNot(contains('2026-07-15')));
    });
  });
}
