import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import '../models/local_uuid.dart';

import '../core/errors/api_exception.dart';
import '../core/network/api_client.dart';
import '../data/local/sync_evidence_store.dart';
import '../models/rabbit.dart';
import '../models/sync_operation.dart';
import '../models/sync_status.dart';
import 'auth_service.dart';
import 'connectivity_gate.dart';
import 'rabbit_local_store.dart';
import 'sync_engine.dart';
import 'r3_publisher.dart';

/// Rabbit API + Drift cache/queue. [SyncEngine] drains pending operations.
class RabbitService {
  RabbitService(
    this._client,
    this._local, {
    ConnectivityGate? connectivity,
    AuthService? auth,
    Future<bool> Function()? authorizePublication,
    bool Function()? remoteAllowed,
    bool r3PublicationEnabled = false,
    SyncEvidenceStore? r3Evidence,
    bool Function()? scopeCurrent,
  })  : _auth = auth,
        _r3PublicationEnabled = r3PublicationEnabled,
        _authorizePublication = authorizePublication,
        _remoteAllowed = remoteAllowed,
        _connectivity = connectivity ?? FakeConnectivity(online: true),
        _engine = SyncEngine(
          _client,
          _local,
          connectivity ?? FakeConnectivity(online: true),
          authorizePublication: authorizePublication,
          remoteAllowed: remoteAllowed,
          scopeCurrent: scopeCurrent,
          r3Publisher:
              r3Evidence == null ? null : R3Publisher(_client, r3Evidence),
        );

  final ApiClient _client;
  final RabbitLocalStore _local;
  final ConnectivityGate _connectivity;
  final SyncEngine _engine;
  final AuthService? _auth;
  final bool _r3PublicationEnabled;
  final Future<bool> Function()? _authorizePublication;
  final bool Function()? _remoteAllowed;
  RabbitService? _accountService;
  int? _accountGeneration;

  int? get generation => _auth?.generation;

  void disconnected() => _auth?.markDisconnected();

  Future<T> _scoped<T>(Future<T> Function(RabbitService) action) async {
    final auth = _auth!;
    final generation = auth.generation;
    if (!await _connectivity.isOnline()) auth.markDisconnected();
    if (!auth.localDataUnlocked ||
        !await auth.canAccessLocally() ||
        !auth.localDataUnlocked ||
        generation != auth.generation) {
      throw ApiException('No hay una sesión autorizada',
          code: 'session_changed');
    }
    final owner = auth.ownerId;
    if (owner == null) {
      throw ApiException('No hay una cuenta autorizada',
          code: 'session_changed');
    }
    bool isCurrent() =>
        auth.generation == generation &&
        auth.ownerId == owner &&
        auth.localDataUnlocked;
    if (_accountGeneration != generation) {
      _accountGeneration = generation;
      _accountService = RabbitService(
        _client,
        _local.forOwner(owner, isCurrent),
        connectivity: _connectivity,
        authorizePublication: () async =>
            isCurrent() &&
            await auth.verifySession() == SessionVerification.verified &&
            isCurrent() &&
            auth.remoteVerified,
        remoteAllowed: () => isCurrent() && auth.remoteVerified,
        scopeCurrent: isCurrent,
        r3Evidence: _r3PublicationEnabled
            ? _local.syncEvidence(owner, generation, isCurrent)
            : null,
      );
    }
    final result = await action(_accountService!);
    if (!isCurrent()) {
      throw ApiException('La sesión cambió', code: 'session_changed');
    }
    return result;
  }

  void _requireRemote() {
    _local.checkSession();
    if (_remoteAllowed?.call() == false) {
      throw ApiException('Servidor no verificado para esta sesión',
          code: 'network');
    }
  }

  static const String _path = '/api/rabbits/';

  Future<List<Rabbit>> readLocalRabbits() => _auth == null
      ? _local.readActive()
      : _scoped((service) => service.readLocalRabbits());

  Future<List<SyncOperation>> readPendingOperations() => _auth == null
      ? _local.readPendingOperations()
      : _scoped((service) => service.readPendingOperations());

  Future<List<SyncOperation>> readRetryableOperations() => _auth == null
      ? _local.readRetryableOperations()
      : _scoped((service) => service.readRetryableOperations());

  Future<List<SyncOperation>> readConflictOperations() => _auth == null
      ? _local.readConflictOperations()
      : _scoped((service) => service.readConflictOperations());

  Future<void> syncPending() => _auth == null
      ? _engine.syncPending()
      : _scoped((service) => service.syncPending());

  void requestR3Publication() {
    if (!_r3PublicationEnabled) return;
    unawaited(syncPending().catchError((Object error) {
      developer.log('R3 publication deferred', name: 'CuniSmart.Sync');
    }));
  }

  Future<List<Rabbit>> fetchRabbits() async {
    if (_auth != null) return _scoped((service) => service.fetchRabbits());
    try {
      _requireRemote();
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
    if (_auth != null) return _scoped((service) => service.lookupByUuid(uuid));
    final local = await _local.readByUuid(uuid);
    if (local != null && local.deletedAt == null) {
      return local;
    }
    if (_local.ownerId != null && local?.deletedAt != null) {
      throw ApiException('El animal fue eliminado');
    }
    if (_remoteAllowed?.call() == false || !await _connectivity.isOnline()) {
      throw ApiException('El animal no está disponible localmente');
    }
    try {
      _requireRemote();
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
    if (_auth != null) return _scoped((service) => service.fetchRabbit(uuid));
    if (_local.ownerId != null) {
      final local = await _local.readByUuid(uuid);
      if (local != null && local.deletedAt == null) return local;
      if (local?.deletedAt != null) {
        throw ApiException('El animal fue eliminado');
      }
      return lookupByUuid(uuid);
    }
    try {
      _requireRemote();
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
    String genealogyKnowledge = 'UNKNOWN',
    String? uuid,
  }) async {
    if (_auth != null) {
      return _scoped((service) => service.createRabbit(
          name: name,
          breed: breed,
          sex: sex,
          birthDate: birthDate,
          weight: weight,
          status: status,
          notes: notes,
          genealogyKnowledge: genealogyKnowledge,
          uuid: uuid));
    }
    final localUuid = uuid ?? newLocalUuid();
    final bodyMap = <String, dynamic>{
      'uuid': localUuid,
      'name': name,
      'breed': breed,
      'sex': sex,
      'birth_date': birthDate,
      'status': status,
      'notes': notes,
      'genealogy_knowledge': genealogyKnowledge,
      if (weight != null) 'weight': weight,
    };
    try {
      _requireRemote();
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
        genealogyKnowledge: genealogyKnowledge,
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
    String? genealogyKnowledge,
  }) async {
    if (_auth != null) {
      return _scoped((service) => service.updateRabbit(
          name: name,
          breed: breed,
          sex: sex,
          birthDate: birthDate,
          weight: weight,
          status: status,
          notes: notes,
          genealogyKnowledge: genealogyKnowledge,
          uuid: uuid));
    }
    final current = await _local.readByUuid(uuid);
    if (_local.ownerId != null) {
      if (current == null || current.deletedAt != null) {
        throw ApiException('El animal no está disponible en esta cuenta');
      }
      if (current.syncStatus == RabbitSyncStatus.conflict) {
        throw ApiException('Resuelve el conflicto antes de editar');
      }
      if (current.syncStatus != RabbitSyncStatus.synced) {
        return _updateOffline(
          uuid: uuid,
          name: name,
          breed: breed,
          sex: sex,
          birthDate: birthDate,
          weight: weight,
          status: status,
          notes: notes,
          genealogyKnowledge: genealogyKnowledge,
        );
      }
    }
    final bodyMap = <String, dynamic>{
      'name': name,
      'breed': breed,
      'sex': sex,
      'birth_date': birthDate,
      'status': status,
      'notes': notes,
      'genealogy_knowledge':
          genealogyKnowledge ?? current?.genealogyKnowledge ?? 'UNKNOWN',
      'version': current?.version ?? 1,
      if (weight != null) 'weight': weight,
    };
    try {
      _requireRemote();
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
          genealogyKnowledge: genealogyKnowledge,
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
        genealogyKnowledge: genealogyKnowledge,
      );
    } catch (e, st) {
      Error.throwWithStackTrace(
        ApiException('Network or parse error: $e'),
        st,
      );
    }
  }

  Future<void> deleteRabbit(String uuid) async {
    if (_auth != null) return _scoped((service) => service.deleteRabbit(uuid));
    if (_local.ownerId != null) {
      final current = await _local.readByUuid(uuid);
      if (current == null || current.deletedAt != null) {
        throw ApiException('El animal no está disponible en esta cuenta');
      }
      if (current.syncStatus == RabbitSyncStatus.conflict) {
        throw ApiException('Resuelve el conflicto antes de eliminar');
      }
      if (current.syncStatus != RabbitSyncStatus.synced) {
        await _deleteOffline(uuid);
        return;
      }
    }
    try {
      _requireRemote();
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
    required String genealogyKnowledge,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final rabbit = Rabbit(
      id: 0,
      userId: _local.ownerId ?? 0,
      uuid: uuid,
      name: name,
      breed: breed,
      sex: sex,
      birthDate: birthDate,
      weight: weight,
      status: status,
      notes: notes,
      genealogyKnowledge: genealogyKnowledge,
      version: 1,
      createdAt: now,
      updatedAt: now,
      syncStatus: RabbitSyncStatus.pendingCreate,
    );
    await _local.transaction(() async {
      await _local.upsert(rabbit);
      await _local.enqueueOrCoalesce(
        rabbitUuid: uuid,
        type: SyncOperationType.create,
        payload: jsonEncode(_payloadFrom(rabbit)),
        baseVersion: 1,
      );
    });
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
    String? genealogyKnowledge,
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
      genealogyKnowledge: genealogyKnowledge ?? current.genealogyKnowledge,
      updatedAt: now,
      syncStatus: stillCreate
          ? RabbitSyncStatus.pendingCreate
          : RabbitSyncStatus.pendingUpdate,
    );
    await _local.transaction(() async {
      await _local.upsert(updated);
      await _local.enqueueOrCoalesce(
        rabbitUuid: uuid,
        type: SyncOperationType.update,
        payload: jsonEncode(_payloadFrom(updated)),
        baseVersion: current.version,
        beforeUpdate: current,
      );
    });
    return updated;
  }

  Future<void> _deleteOffline(String uuid) => _local.transaction(() async {
        final current = await _local.readByUuid(uuid);
        await _local.enqueueOrCoalesce(
          rabbitUuid: uuid,
          type: SyncOperationType.delete,
          payload: jsonEncode({'uuid': uuid}),
          baseVersion: current?.version ?? 1,
        );
        final remaining = await _local.readByUuid(uuid);
        if (remaining != null) {
          await _local.markDeleted(uuid,
              status: RabbitSyncStatus.pendingDelete);
        }
      });

  Map<String, dynamic> _payloadFrom(Rabbit rabbit) {
    return <String, dynamic>{
      'uuid': rabbit.uuid,
      'name': rabbit.name,
      'breed': rabbit.breed,
      'sex': rabbit.sex,
      'birth_date': rabbit.birthDate,
      'status': rabbit.status,
      'notes': rabbit.notes,
      'genealogy_knowledge': rabbit.genealogyKnowledge,
      'version': rabbit.version,
      if (rabbit.weight != null) 'weight': rabbit.weight,
    };
  }

  Future<void> resolveConflictKeepRemote(String uuid) async {
    if (_auth != null) {
      return _scoped((service) => service.resolveConflictKeepRemote(uuid));
    }
    final op = await _local.readConflictForUuid(uuid);
    if (op == null || op.serverSnapshot == null) {
      throw ApiException('No hay un conflicto para resolver');
    }
    final decoded = jsonDecode(op.serverSnapshot!) as Map<String, dynamic>;
    final remote = Rabbit.fromJson(decoded);
    if (remote.uuid != uuid) throw ApiException('Conflicto de otro registro');
    await _local.transaction(() async {
      await _local.upsert(remote.copyWith(syncStatus: RabbitSyncStatus.synced));
      await _local.markOperation(id: op.id, status: SyncOpStatus.completed);
    });
  }

  Future<void> resolveConflictKeepLocal(String uuid) async {
    if (_auth != null) {
      return _scoped((service) => service.resolveConflictKeepLocal(uuid));
    }
    final authorize = _authorizePublication;
    if (authorize != null) {
      if (!await _connectivity.isOnline() || !await authorize()) {
        throw ApiException('Verifica la sesión antes de publicar');
      }
    }
    _requireRemote();
    final op = await _local.readConflictForUuid(uuid);
    final local = await _local.readByUuid(uuid);
    if (op == null || local == null || op.serverSnapshot == null) {
      throw ApiException('No hay un conflicto para resolver');
    }
    final remote = jsonDecode(op.serverSnapshot!) as Map<String, dynamic>;
    final remoteVersion = (remote['version'] as num?)?.toInt() ?? local.version;
    _requireRemote();
    final raw = await _client.put(
      '$_path$uuid/',
      body: jsonEncode(_payloadFrom(local.copyWith(version: remoteVersion))),
      retryOnUnauthorized: false,
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    );
    final updated = Rabbit.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    _requireRemote();
    if (updated.uuid != uuid) throw ApiException('UUID de respuesta inválido');
    await _local.transaction(() async {
      await _local
          .upsert(updated.copyWith(syncStatus: RabbitSyncStatus.synced));
      await _local.markOperation(id: op.id, status: SyncOpStatus.completed);
    });
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
    if (e.statusCode == 401 && _remoteAllowed?.call() == false) return true;
    final code = e.statusCode;
    if (code == null) return true;
    return code >= 500;
  }
}
