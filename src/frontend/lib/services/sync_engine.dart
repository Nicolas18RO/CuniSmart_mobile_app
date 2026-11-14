import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import '../core/errors/api_exception.dart';
import '../core/network/api_client.dart';
import '../models/rabbit.dart';
import '../models/sync_operation.dart';
import '../models/sync_status.dart';
import 'connectivity_gate.dart';
import 'rabbit_local_store.dart';
import 'r3_publisher.dart';

/// Drains retryable [sync_operations] when online. HTTP 409 becomes CONFLICT.
class SyncEngine {
  SyncEngine(
    this._client,
    this._local,
    this._connectivity, {
    this.authorizePublication,
    this.remoteAllowed,
    this.r3Publisher,
    this.scopeCurrent,
  });

  final ApiClient _client;
  final RabbitLocalStore _local;
  final ConnectivityGate _connectivity;
  final Future<bool> Function()? authorizePublication;
  final bool Function()? remoteAllowed;
  final R3Publisher? r3Publisher;
  final bool Function()? scopeCurrent;

  static const String _path = '/api/rabbits/';

  bool _inFlight = false;
  bool _requested = false;
  Timer? _wake;
  DateTime? _wakeAt;

  Future<void> syncPending() async {
    _requested = true;
    if (_inFlight) return;
    _inFlight = true;
    try {
      do {
        _requested = false;
        if (scopeCurrent?.call() == false) return;
        if (!await _connectivity.isOnline()) continue;
        if (authorizePublication != null && !await authorizePublication!()) {
          continue;
        }
        if (!await _canPublish()) continue;
        final ops = await _local.readRetryableOperations();
        for (final op in ops) {
          if (!await _canPublish()) break;
          await _process(op);
        }
        if (await _canPublish()) {
          await r3Publisher?.drain(
              _canPublish, _schedule, authorizePublication);
        }
      } while (_requested);
    } finally {
      _inFlight = false;
    }
  }

  void _schedule(Duration delay) {
    final due = DateTime.now().add(delay);
    if (_wakeAt != null && !_wakeAt!.isAfter(due)) return;
    _wake?.cancel();
    _wakeAt = due;
    _wake = Timer(delay, () {
      _wakeAt = null;
      if (scopeCurrent?.call() == false) return;
      unawaited(syncPending().catchError((Object error) {
        // A concurrent logout can invalidate a scheduled drain.
        if (scopeCurrent?.call() != false) {
          developer.log('Scheduled sync interrupted', name: 'CuniSmart.Sync');
        }
      }));
    });
  }

  Future<bool> _canPublish() async {
    if (!await _connectivity.isOnline()) return false;
    return remoteAllowed?.call() ?? true;
  }

  Future<void> _checkBeforeSend() async {
    if (!await _canPublish()) {
      throw ApiException('Publicación suspendida',
          code: 'publication_suspended');
    }
    _checkPublication();
  }

  void _checkPublication() {
    _local.checkSession();
    if (remoteAllowed?.call() == false) {
      throw ApiException('Publicación suspendida',
          code: 'publication_suspended');
    }
  }

  Future<void> _process(SyncOperation op) async {
    _checkPublication();
    final attempts = op.attempts + 1;
    await _local.markOperation(
      id: op.id,
      status: SyncOpStatus.syncing,
      attempts: attempts,
    );
    try {
      switch (op.operationType) {
        case SyncOperationType.create:
          await _pushCreate(op);
        case SyncOperationType.update:
          await _pushUpdate(op);
        case SyncOperationType.delete:
          await _pushDelete(op);
      }
    } on ApiException catch (e) {
      if (remoteAllowed?.call() == false) return;
      await _local.markOperation(
        id: op.id,
        status: SyncOpStatus.failed,
        attempts: attempts,
        lastError: _errorText(e),
      );
    } catch (e) {
      if (remoteAllowed?.call() == false) return;
      await _local.markOperation(
        id: op.id,
        status: SyncOpStatus.failed,
        attempts: attempts,
        lastError: e.toString(),
      );
    }
  }

  Future<void> _pushCreate(SyncOperation op) async {
    try {
      await _checkBeforeSend();
      _checkPublication();
      final raw = await _client.post(
        _path,
        body: op.payload,
        retryOnUnauthorized: false,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      );
      await _completeRabbit(op, raw);
    } on ApiException catch (e) {
      if (e.statusCode == 400) {
        await _checkBeforeSend();
        _checkPublication();
        final raw = await _client.get(
          '$_path${op.rabbitUuid}/',
          retryOnUnauthorized: false,
          headers: {'Accept': 'application/json'},
        );
        await _completeRabbit(op, raw);
        return;
      }
      rethrow;
    }
  }

  Future<void> _pushUpdate(SyncOperation op) async {
    try {
      await _checkBeforeSend();
      _checkPublication();
      final raw = await _client.put(
        '$_path${op.rabbitUuid}/',
        body: op.payload,
        retryOnUnauthorized: false,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      );
      await _completeRabbit(op, raw);
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        await _applyConflict(op, e);
        return;
      }
      rethrow;
    }
  }

  Future<void> _applyConflict(SyncOperation op, ApiException error) async {
    _checkPublication();
    final snapshot = snapshotJsonFrom409(error);
    await _local.transaction(() async {
      await _local.markOperation(
        id: op.id,
        status: SyncOpStatus.conflict,
        lastError: 'El conejo fue modificado en otro lugar.',
        serverSnapshot: snapshot,
      );
      final local = await _local.readByUuid(op.rabbitUuid);
      if (local != null) {
        await _local
            .upsert(local.copyWith(syncStatus: RabbitSyncStatus.conflict));
      }
      _checkPublication();
    });
  }

  Future<void> _pushDelete(SyncOperation op) async {
    try {
      await _checkBeforeSend();
      _checkPublication();
      await _client.delete(
        '$_path${op.rabbitUuid}/',
        retryOnUnauthorized: false,
        headers: {'Accept': 'application/json'},
      );
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
    }
    _checkPublication();
    await _local.transaction(() async {
      await _local.markDeleted(op.rabbitUuid, status: RabbitSyncStatus.synced);
      await _local.markOperation(id: op.id, status: SyncOpStatus.completed);
      _checkPublication();
    });
  }

  Future<void> _completeRabbit(SyncOperation op, String raw) async {
    _checkPublication();
    final rabbit = Rabbit.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    if (rabbit.uuid != op.rabbitUuid) {
      throw ApiException('UUID de respuesta inválido');
    }
    await _local.transaction(() async {
      await _local.upsert(rabbit.copyWith(syncStatus: RabbitSyncStatus.synced));
      await _local.markOperation(id: op.id, status: SyncOpStatus.completed);
      _checkPublication();
    });
  }

  String _errorText(ApiException e) {
    final code = e.statusCode;
    if (code != null) return 'Error $code: ${e.message}';
    return e.message;
  }
}

String snapshotJsonFrom409(ApiException error) {
  try {
    final decoded = jsonDecode(error.rawBody ?? error.message);
    if (decoded is Map<String, dynamic>) {
      final current = decoded['current'] ??
          (decoded['detail'] is Map ? decoded['detail']['current'] : null);
      if (current is Map<String, dynamic>) {
        return jsonEncode(current);
      }
    }
  } catch (_) {}
  return error.message;
}
