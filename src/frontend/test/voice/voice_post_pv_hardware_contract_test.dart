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
import 'package:frontend/services/voice_service.dart';
import 'package:frontend/viewmodels/rabbit_viewmodel.dart';
import 'package:frontend/viewmodels/sensor_viewmodel.dart';
import 'package:frontend/viewmodels/voice_viewmodel.dart';
import 'package:frontend/voice/hardware/hardware_voice_trigger.dart';
import 'package:frontend/voice/hardware/volume_up_long_press_voice_trigger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VE-HW-06 Noop does not crash (characterization)', () {
    test('Noop start/stop/onTrigger safe', () {
      final t = NoopHardwareVoiceTrigger();
      var n = 0;
      t.onTrigger = () => n++;
      t.start();
      t.stop();
      expect(n, 0);
    });
  });

  group('VE-HW-02 VoiceViewModel must call start() on injected trigger', () {
    test('start() invoked during VoiceViewModel construction', () {
      final recording = _RecordingHardwareTrigger();
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final vm = VoiceViewModel(
        VoiceService(),
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
        hardwareVoiceTrigger: recording,
      );
      addTearDown(vm.dispose);

      expect(recording.startCalled, isTrue);
      expect(recording.onTrigger, isNotNull);
    });
  });

  group('VE-HW-03 onTrigger wired to mic path', () {
    test('VM assigns onTrigger callback (same entry as FAB)', () {
      final recording = _RecordingHardwareTrigger();
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final vm = VoiceViewModel(
        VoiceService(),
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
        hardwareVoiceTrigger: recording,
      );
      addTearDown(vm.dispose);
      expect(recording.onTrigger, isNotNull);
    });
  });

  group('VE-HW-01 / 04 / 05 VolumeUpLongPressVoiceTrigger', () {
    test('VE-HW-01 production long-press trigger is Volume Up', () {
      final t = VolumeUpLongPressVoiceTrigger(attachHardwareKeyboard: false);
      expect(t, isA<HardwareVoiceTrigger>());
      expect(t.longPressThreshold, const Duration(milliseconds: 700));
      expect(t.volumeKey, LogicalKeyboardKey.audioVolumeUp);
    });

    test('VE-HW-04 short press must not fire onTrigger', () {
      var fired = 0;
      var clock = DateTime.utc(2026, 1, 1, 12);
      final t = VolumeUpLongPressVoiceTrigger(
        attachHardwareKeyboard: false,
        now: () => clock,
        longPressThreshold: const Duration(milliseconds: 700),
      );
      t.onTrigger = () => fired++;
      t.start();
      t.handleVolumeUpDown();
      clock = clock.add(const Duration(milliseconds: 200));
      t.tick();
      t.handleVolumeUpUp();
      expect(fired, 0);
    });

    test('VE-HW-05 long press ≥ threshold fires once per gesture', () {
      var fired = 0;
      var clock = DateTime.utc(2026, 1, 1, 12);
      final t = VolumeUpLongPressVoiceTrigger(
        attachHardwareKeyboard: false,
        now: () => clock,
        longPressThreshold: const Duration(milliseconds: 700),
      );
      t.onTrigger = () => fired++;
      t.start();

      t.handleVolumeUpDown();
      clock = clock.add(const Duration(milliseconds: 800));
      t.tick();
      expect(fired, 1);
      t.tick();
      expect(fired, 1);

      t.handleVolumeUpUp();
      t.handleVolumeUpDown();
      clock = clock.add(const Duration(milliseconds: 800));
      t.tick();
      expect(fired, 2);

      t.stop();
    });
  });
}

class _RecordingHardwareTrigger implements HardwareVoiceTrigger {
  bool startCalled = false;
  bool stopCalled = false;

  @override
  void Function()? onTrigger;

  @override
  void start() {
    startCalled = true;
  }

  @override
  void stop() {
    stopCalled = true;
  }
}
