import 'dart:convert';
import 'dart:math';

import '../core/errors/api_exception.dart';
import '../core/network/api_client.dart';
import '../models/rabbit.dart';
import '../models/sync_operation.dart';
import '../models/sync_status.dart';
import 'connectivity_gate.dart';
import 'rabbit_local_store.dart';
import 'sync_engine.dart';

/// Rabbit API + Drift cache/queue. [SyncEngine] drains pending operations.
class RabbitService {
  RabbitService(
    this._client,
    this._local, {
    ConnectivityGate? connectivity,
  })  : _connectivity = connectivity ?? FakeConnectivity(online: true),
        _engine = SyncEngine(
          _client,
          _local,
          connectivity ?? FakeConnectivity(online: true),
        );

  final ApiClient _client;
  final RabbitLocalStore _local;
  final ConnectivityGate _connectivity;
  final SyncEngine _engine;

  static const String _path = '/api/rabbits/';

  Future<List<Rabbit>> readLocalRabbits() => _local.readActive();

  Future<List<SyncOperation>> readPendingOperations() =>
      _local.readPendingOperations();

  Future<List<SyncOperation>> readRetryableOperations() =>
      _local.readRetryableOperations();

  Future<List<SyncOperation>> readConflictOperations() =>
      _local.readConflictOperations();

  Future<void> syncPending() => _engine.syncPending();

  Future<List<Rabbit>> fetchRabbits() async {
    try {
      final raw = await _client.get(
        _path,
        headers: {'Accept': 'application/json'},
      );
      final decoded = jsonDecode(raw) as dynamic;
      if (decoded is! List) {
        throw ApiException('Expected JSON array from GET $_path');
      }
      final list = decoded
          .map((e) => Rabbit.fromJson(e as Map<String, dynamic>))
          .toList();
      await _local.persistSynced(list);
      return _local.readActive();
    } on ApiException {
      rethrow;
    } catch (e, st) {
      Error.throwWithStackTrace(
        ApiException('Network or parse error: $e'),
        st,
      );
    }
  }

  Future<Rabbit> lookupByUuid(String uuid) async {
    final local = await _local.readByUuid(uuid);
    if (local != null && local.deletedAt == null) {
      return local;
    }
    if (!await _connectivity.isOnline()) {
      throw ApiException('El animal no está disponible localmente');
    }
    try {
      final raw = await _client.get(
        '$_path$uuid/',
        headers: {'Accept': 'application/json'},
      );
      final rabbit = Rabbit.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      await _local.upsert(rabbit.copyWith(syncStatus: RabbitSyncStatus.synced));
      return rabbit;
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        throw ApiException('No se encontró el conejo', statusCode: 404);
      }
      rethrow;
    } catch (e, st) {
      Error.throwWithStackTrace(
        ApiException('Network or parse error: $e'),
        st,
      );
    }
  }

  Future<Rabbit> fetchRabbit(String uuid) async {
    try {
      final path = '$_path$uuid/';
      final raw = await _client.get(
        path,
        headers: {'Accept': 'application/json'},
      );
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return Rabbit.fromJson(decoded);
    } on ApiException catch (e) {
      if (_isUnavailable(e)) {
        final local = await _local.readByUuid(uuid);
        if (local != null && local.deletedAt == null) return local;
      }
      rethrow;
    } catch (e, st) {
      Error.throwWithStackTrace(
        ApiException('Network or parse error: $e'),
        st,
      );
    }
  }

  Future<Rabbit> createRabbit({
    required String name,
    required String breed,
    required String sex,
    required String birthDate,
    double? weight,
    required String status,
    String notes = '',
    String? uuid,
  }) async {
    final localUuid = uuid ?? _newUuid();
    final bodyMap = <String, dynamic>{
      'uuid': localUuid,
      'name': name,
      'breed': breed,
      'sex': sex,
      'birth_date': birthDate,
      'status': status,
      'notes': notes,
      if (weight != null) 'weight': weight,
    };
    try {
      final raw = await _client.post(
        _path,
        body: jsonEncode(bodyMap),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      );
      final created = Rabbit.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      await _local.upsert(created);
      return created;
    } on ApiException catch (e) {
      if (!_isUnavailable(e)) rethrow;
      return _createOffline(
        uuid: localUuid,
        name: name,
        breed: breed,
        sex: sex,
        birthDate: birthDate,
        weight: weight,
        status: status,
        notes: notes,
      );
    } catch (e, st) {
      Error.throwWithStackTrace(
        ApiException('Network or parse error: $e'),
        st,
      );
    }
  }

  Future<Rabbit> updateRabbit({
    required String uuid,
    required String name,
    required String breed,
    required String sex,
    required String birthDate,
    double? weight,
    required String status,
    String notes = '',
  }) async {
    final current = await _local.readByUuid(uuid);
    final bodyMap = <String, dynamic>{
      'name': name,
      'breed': breed,
      'sex': sex,
      'birth_date': birthDate,
      'status': status,
      'notes': notes,
      'version': current?.version ?? 1,
      if (weight != null) 'weight': weight,
    };
    try {
      final raw = await _client.put(
        '$_path$uuid/',
        body: jsonEncode(bodyMap),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      );
      final updated = Rabbit.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      await _local.upsert(updated);
      return updated;
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        await _updateOffline(
          uuid: uuid,
          name: name,
          breed: breed,
          sex: sex,
          birthDate: birthDate,
          weight: weight,
          status: status,
          notes: notes,
        );
        await _recordOnlineConflict(uuid, e);
        return (await _local.readByUuid(uuid))!;
      }
      if (!_isUnavailable(e)) rethrow;
      return _updateOffline(
        uuid: uuid,
        name: name,
        breed: breed,
        sex: sex,
        birthDate: birthDate,
        weight: weight,
        status: status,
        notes: notes,
      );
    } catch (e, st) {
      Error.throwWithStackTrace(
        ApiException('Network or parse error: $e'),
        st,
      );
    }
  }

  Future<void> deleteRabbit(String uuid) async {
    try {
      await _client.delete(
        '$_path$uuid/',
        headers: {'Accept': 'application/json'},
      );
      await _local.markDeleted(uuid, status: RabbitSyncStatus.synced);
    } on ApiException catch (e) {
      if (!_isUnavailable(e)) rethrow;
      await _deleteOffline(uuid);
    } catch (e, st) {
      Error.throwWithStackTrace(
        ApiException('Network or parse error: $e'),
        st,
      );
    }
  }

  Future<Rabbit> _createOffline({
    required String uuid,
    required String name,
    required String breed,
    required String sex,
    required String birthDate,
    double? weight,
    required String status,
    required String notes,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final rabbit = Rabbit(
      id: 0,
      uuid: uuid,
      name: name,
      breed: breed,
      sex: sex,
      birthDate: birthDate,
      weight: weight,
      status: status,
      notes: notes,
      version: 1,
      createdAt: now,
      updatedAt: now,
      syncStatus: RabbitSyncStatus.pendingCreate,
    );
    await _local.upsert(rabbit);
    await _local.enqueueOrCoalesce(
      rabbitUuid: uuid,
      type: SyncOperationType.create,
      payload: jsonEncode(_payloadFrom(rabbit)),
      baseVersion: 1,
    );
    return rabbit;
  }

  Future<Rabbit> _updateOffline({
    required String uuid,
    required String name,
    required String breed,
    required String sex,
    required String birthDate,
    double? weight,
    required String status,
    required String notes,
  }) async {
    final current = await _local.readByUuid(uuid);
    if (current == null) {
      throw ApiException('No se encontró el conejo en el dispositivo');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final stillCreate = current.syncStatus == RabbitSyncStatus.pendingCreate;
    final updated = current.copyWith(
      name: name,
      breed: breed,
      sex: sex,
      birthDate: birthDate,
      weight: weight,
      clearWeight: weight == null,
      status: status,
      notes: notes,
      updatedAt: now,
      syncStatus: stillCreate
          ? RabbitSyncStatus.pendingCreate
          : RabbitSyncStatus.pendingUpdate,
    );
    await _local.upsert(updated);
    await _local.enqueueOrCoalesce(
      rabbitUuid: uuid,
      type: SyncOperationType.update,
      payload: jsonEncode(_payloadFrom(updated)),
      baseVersion: current.version,
    );
    return updated;
  }

  Future<void> _deleteOffline(String uuid) async {
    final current = await _local.readByUuid(uuid);
    await _local.enqueueOrCoalesce(
      rabbitUuid: uuid,
      type: SyncOperationType.delete,
      payload: jsonEncode({'uuid': uuid}),
      baseVersion: current?.version ?? 1,
    );
    final remaining = await _local.readByUuid(uuid);
    if (remaining != null) {
      await _local.markDeleted(uuid, status: RabbitSyncStatus.pendingDelete);
    }
  }

  Map<String, dynamic> _payloadFrom(Rabbit rabbit) {
    return <String, dynamic>{
      'uuid': rabbit.uuid,
      'name': rabbit.name,
      'breed': rabbit.breed,
      'sex': rabbit.sex,
      'birth_date': rabbit.birthDate,
      'status': rabbit.status,
      'notes': rabbit.notes,
      'version': rabbit.version,
      if (rabbit.weight != null) 'weight': rabbit.weight,
    };
  }

  Future<void> resolveConflictKeepRemote(String uuid) async {
    final op = await _local.readConflictForUuid(uuid);
    if (op == null || op.serverSnapshot == null) {
      throw ApiException('No hay un conflicto para resolver');
    }
    final decoded = jsonDecode(op.serverSnapshot!) as Map<String, dynamic>;
    final remote = Rabbit.fromJson(decoded);
    await _local.upsert(remote.copyWith(syncStatus: RabbitSyncStatus.synced));
    await _local.markOperation(id: op.id, status: SyncOpStatus.completed);
  }

  Future<void> resolveConflictKeepLocal(String uuid) async {
    final op = await _local.readConflictForUuid(uuid);
    final local = await _local.readByUuid(uuid);
    if (op == null || local == null || op.serverSnapshot == null) {
      throw ApiException('No hay un conflicto para resolver');
    }
    final remote = jsonDecode(op.serverSnapshot!) as Map<String, dynamic>;
    final remoteVersion = (remote['version'] as num?)?.toInt() ?? local.version;
    final raw = await _client.put(
      '$_path$uuid/',
      body: jsonEncode(_payloadFrom(local.copyWith(version: remoteVersion))),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    );
    final updated = Rabbit.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    await _local.upsert(updated.copyWith(syncStatus: RabbitSyncStatus.synced));
    await _local.markOperation(id: op.id, status: SyncOpStatus.completed);
  }

  Future<void> _recordOnlineConflict(String uuid, ApiException error) async {
    final snapshot = snapshotJsonFrom409(error);
    final pending = await _local.readPendingOperations();
    final match = pending.where((o) => o.rabbitUuid == uuid).toList();
    if (match.isNotEmpty) {
      await _local.markOperation(
        id: match.first.id,
        status: SyncOpStatus.conflict,
        lastError: 'El conejo fue modificado en otro lugar.',
        serverSnapshot: snapshot,
      );
    } else {
      await _local.enqueueOrCoalesce(
        rabbitUuid: uuid,
        type: SyncOperationType.update,
        payload: jsonEncode(_payloadFrom((await _local.readByUuid(uuid))!)),
        baseVersion: (await _local.readByUuid(uuid))?.version ?? 1,
      );
      final created = await _local.readConflictForUuid(uuid);
      final pendingNow = (await _local.readPendingOperations())
          .where((o) => o.rabbitUuid == uuid);
      final op = created ?? (pendingNow.isEmpty ? null : pendingNow.first);
      if (op != null) {
        await _local.markOperation(
          id: op.id,
          status: SyncOpStatus.conflict,
          lastError: 'El conejo fue modificado en otro lugar.',
          serverSnapshot: snapshot,
        );
      }
    }
    final local = await _local.readByUuid(uuid);
    if (local != null) {
      await _local
          .upsert(local.copyWith(syncStatus: RabbitSyncStatus.conflict));
    }
  }

  bool _isUnavailable(ApiException e) {
    if (e.code == 'network') return true;
    final code = e.statusCode;
    if (code == null) return true;
    return code >= 500;
  }

  String _newUuid() {
    final rnd = Random.secure();
    final b = List<int>.generate(16, (_) => rnd.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
    return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}-${h(8)}${h(9)}-${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
  }
}
