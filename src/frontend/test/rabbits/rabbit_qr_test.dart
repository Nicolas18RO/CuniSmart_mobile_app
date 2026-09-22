import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend/core/errors/api_exception.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/state/submit_state.dart';
import 'package:frontend/data/local/app_database.dart';
import 'package:frontend/models/rabbit.dart';
import 'package:frontend/models/rabbit_qr.dart';
import 'package:frontend/services/connectivity_gate.dart';
import 'package:frontend/services/rabbit_local_store.dart';
import 'package:frontend/services/rabbit_service.dart';
import 'package:frontend/viewmodels/rabbit_viewmodel.dart';

const _luna = Rabbit(
  id: 7,
  uuid: '11111111-1111-1111-1111-111111111111',
  userId: 4,
  name: 'Luna',
  breed: 'Rex',
  sex: 'female',
  birthDate: '2024-01-15',
  weight: 2.5,
  status: 'active',
  notes: '',
  version: 1,
  createdAt: '2024-01-01T00:00:00Z',
  updatedAt: '2024-01-01T00:00:00Z',
);

Map<String, dynamic> _remoteJson() => {
      'id': 7,
      'uuid': _luna.uuid,
      'user': 4,
      'name': 'Luna',
      'breed': 'Rex',
      'sex': 'female',
      'birth_date': '2024-01-15',
      'weight': 2.5,
      'status': 'active',
      'notes': '',
      'version': 1,
      'created_at': '2024-01-01T00:00:00Z',
      'updated_at': '2024-01-01T00:00:00Z',
    };

RabbitService _service(
  AppDatabase db,
  http.Client client, {
  required bool online,
}) {
  return RabbitService(
    ApiClient(httpClient: client),
    RabbitLocalStore(db),
    connectivity: FakeConnectivity(online: online),
  );
}

void main() {
  test('QR payload is only the stable URI with the UUID', () {
    final payload = RabbitQr.payloadFor(_luna.uuid);
    expect(payload, 'cunismart://rabbit/${_luna.uuid}');
    expect(payload.contains('Luna'), isFalse);
    expect(payload.contains('Rex'), isFalse);
    expect(payload.contains('weight'), isFalse);
  });

  test('parse extracts UUID from CuniSmart payload or a bare UUID', () {
    expect(RabbitQr.parseUuid(RabbitQr.payloadFor(_luna.uuid)), _luna.uuid);
    expect(RabbitQr.parseUuid(_luna.uuid), _luna.uuid);
    expect(RabbitQr.parseUuid('  ${_luna.uuid}  '), _luna.uuid);
  });

  test('parse rejects names, JSON and unrelated codes', () {
    expect(RabbitQr.parseUuid('Luna'), isNull);
    expect(
        RabbitQr.parseUuid('{"name":"Luna","uuid":"${_luna.uuid}"}'), isNull);
    expect(RabbitQr.parseUuid('https://example.com/${_luna.uuid}'), isNull);
    expect(RabbitQr.parseUuid('cunismart://rabbit/not-a-uuid'), isNull);
  });

  test('lookup finds a local rabbit without calling the API', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await RabbitLocalStore(db).persistSynced([_luna]);
    var gets = 0;
    final service = _service(
      db,
      MockClient((req) async {
        gets += 1;
        return http.Response('[]', 200);
      }),
      online: true,
    );

    final found = await service.lookupByUuid(_luna.uuid);

    expect(found.uuid, _luna.uuid);
    expect(found.name, 'Luna');
    expect(gets, 0);
  });

  test('lookup misses local, GET online persists and returns the rabbit',
      () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    var gets = 0;
    final service = _service(
      db,
      MockClient((req) async {
        gets += 1;
        expect(req.method, 'GET');
        expect(req.url.path, endsWith('/api/rabbits/${_luna.uuid}/'));
        return http.Response(jsonEncode(_remoteJson()), 200);
      }),
      online: true,
    );

    final found = await service.lookupByUuid(_luna.uuid);

    expect(found.name, 'Luna');
    expect(gets, 1);
    final local = await service.readLocalRabbits();
    expect(local.single.uuid, _luna.uuid);
    expect(local.single.name, 'Luna');
  });

  test('lookup misses local offline and reports unavailable', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    var gets = 0;
    final service = _service(
      db,
      MockClient((req) async {
        gets += 1;
        return http.Response(jsonEncode(_remoteJson()), 200);
      }),
      online: false,
    );

    try {
      await service.lookupByUuid(_luna.uuid);
      fail('expected ApiException');
    } on ApiException catch (e) {
      expect(e.message, 'El animal no está disponible localmente');
    }
    expect(gets, 0);
    expect(await service.readLocalRabbits(), isEmpty);
  });

  test('lookup online 404 does not invent a rabbit', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final service = _service(
      db,
      MockClient((_) async => http.Response('{"detail":"Not found."}', 404)),
      online: true,
    );

    try {
      await service.lookupByUuid(_luna.uuid);
      fail('expected ApiException');
    } on ApiException catch (e) {
      expect(e.statusCode, 404);
      expect(e.message, 'No se encontró el conejo');
    }
    expect(await service.readLocalRabbits(), isEmpty);
  });

  test('ViewModel opens the matching rabbit from a valid QR payload', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await RabbitLocalStore(db).persistSynced([_luna]);
    final vm = RabbitViewModel(
      _service(
        db,
        MockClient((_) async => http.Response('[]', 200)),
        online: false,
      ),
    );

    final found = await vm.lookupFromQr(RabbitQr.payloadFor(_luna.uuid));

    expect(found?.name, 'Luna');
    expect(found?.uuid, _luna.uuid);
  });

  test('ViewModel rejects an invalid QR without hitting the store', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final vm = RabbitViewModel(
      _service(
        db,
        MockClient((_) async => http.Response('[]', 200)),
        online: true,
      ),
    );

    final found = await vm.lookupFromQr('{"name":"Luna"}');

    expect(found, isNull);
    expect(
      switch (vm.submitState) {
        SubmitFailed(:final message) => message,
        _ => '',
      },
      'Este código no es de CuniSmart',
    );
  });
}
