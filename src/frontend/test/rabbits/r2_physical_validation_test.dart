import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/data/local/app_database.dart';
import 'package:frontend/models/rabbit_qr.dart';
import 'package:frontend/models/sync_status.dart';
import 'package:frontend/services/connectivity_gate.dart';
import 'package:frontend/services/rabbit_local_store.dart';
import 'package:frontend/services/rabbit_service.dart';
import 'package:frontend/voice/engine/voice_ai_engine.dart';

/// R2.10 golden path: offline create → edit → ficha → QR → reopen → sync.
void main() {
  test('offline create, edit, ficha, QR, reopen and sync to server', () async {
    final dir = await Directory.systemTemp.createTemp('cunismart_r210_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File(p.join(dir.path, 'cunismart.sqlite'));
    final net = FakeConnectivity(online: false);
    addTearDown(net.close);

    Map<String, dynamic>? posted;
    var serverUp = false;
    http.Client client() => MockClient((req) async {
          if (!serverUp) {
            return http.Response('sin conexion', 500);
          }
          if (req.method == 'POST' && req.url.path.endsWith('/api/rabbits/')) {
            posted = jsonDecode(req.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'id': 99,
                'uuid': posted!['uuid'],
                'user': 4,
                'name': posted!['name'],
                'breed': posted!['breed'],
                'sex': posted!['sex'],
                'birth_date': posted!['birth_date'],
                'weight': posted!['weight'],
                'status': posted!['status'],
                'notes': posted!['notes'] ?? '',
                'version': 1,
                'created_at': '2024-06-01T00:00:00Z',
                'updated_at': '2024-06-01T00:00:00Z',
              }),
              201,
            );
          }
          return http.Response('[]', 200);
        });

    RabbitService serviceFor(AppDatabase db) => RabbitService(
          ApiClient(httpClient: client()),
          RabbitLocalStore(db),
          connectivity: net,
        );

    final db1 = AppDatabase.file(file);
    final offline = serviceFor(db1);

    final created = await offline.createRabbit(
      name: 'Nube',
      breed: 'Rex',
      sex: 'female',
      birthDate: '2024-06-01',
      status: 'active',
    );
    final edited = await offline.updateRabbit(
      uuid: created.uuid,
      name: 'Nube',
      breed: 'Rex',
      sex: 'female',
      birthDate: '2024-06-01',
      weight: 2.4,
      status: 'active',
      notes: 'revision',
    );

    expect(edited.syncStatus, RabbitSyncStatus.pendingCreate);
    final ficha = await offline.lookupByUuid(created.uuid);
    expect(ficha.name, 'Nube');
    expect(ficha.notes, 'revision');
    expect(ficha.weight, 2.4);
    expect(VoiceAIEngine.fichaSpeech(ficha), contains('Nube'));
    expect(VoiceAIEngine.fichaSpeech(ficha), contains('revision'));

    final payload = RabbitQr.payloadFor(ficha.uuid);
    expect(RabbitQr.parseUuid(payload), ficha.uuid);
    expect(payload.contains('Nube'), isFalse);

    await db1.close();

    final db2 = AppDatabase.file(file);
    addTearDown(db2.close);
    final afterReopen = serviceFor(db2);
    final restored = await afterReopen.readLocalRabbits();
    expect(restored, hasLength(1));
    expect(restored.single.uuid, created.uuid);
    expect(restored.single.notes, 'revision');
    expect(restored.single.weight, 2.4);
    expect(await afterReopen.readPendingOperations(), hasLength(1));

    final fromQr = await afterReopen.lookupByUuid(
      RabbitQr.parseUuid(payload)!,
    );
    expect(fromQr.name, 'Nube');

    serverUp = true;
    net.setOnline(true);
    await afterReopen.syncPending();

    expect(posted, isNotNull);
    expect(posted!['uuid'], created.uuid);
    expect(posted!['name'], 'Nube');
    expect(posted!['notes'], 'revision');
    expect(posted!['weight'], 2.4);
    expect(await afterReopen.readPendingOperations(), isEmpty);
    final synced = await afterReopen.readLocalRabbits();
    expect(synced.single.syncStatus, RabbitSyncStatus.synced);
    expect(synced.single.id, 99);
  });
}
