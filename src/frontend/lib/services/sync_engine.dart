import 'dart:convert';

import '../core/errors/api_exception.dart';
import '../core/network/api_client.dart';
import '../models/rabbit.dart';
import '../models/sync_operation.dart';
import '../models/sync_status.dart';
import 'connectivity_gate.dart';
import 'rabbit_local_store.dart';

/// Drains retryable [sync_operations] when online. HTTP 409 becomes CONFLICT.
class SyncEngine {
  SyncEngine(this._client, this._local, this._connectivity);

  final ApiClient _client;
  final RabbitLocalStore _local;
  final ConnectivityGate _connectivity;

  static const String _path = '/api/rabbits/';

  bool _inFlight = false;

  Future<void> syncPending() async {
    if (!await _connectivity.isOnline()) return;
    if (_inFlight) return;
    _inFlight = true;
    try {
      final ops = await _local.readRetryableOperations();
      for (final op in ops) {
        await _process(op);
      }
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _process(SyncOperation op) async {
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
      await _local.markOperation(
        id: op.id,
        status: SyncOpStatus.failed,
        attempts: attempts,
        lastError: _errorText(e),
      );
    } catch (e) {
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
      final raw = await _client.post(
        _path,
        body: op.payload,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      );
      await _completeRabbit(op, raw);
    } on ApiException catch (e) {
      if (e.statusCode == 400) {
        final raw = await _client.get(
          '$_path${op.rabbitUuid}/',
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
      final raw = await _client.put(
        '$_path${op.rabbitUuid}/',
        body: op.payload,
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
    final snapshot = snapshotJsonFrom409(error);
    await _local.markOperation(
      id: op.id,
      status: SyncOpStatus.conflict,
      lastError: 'El conejo fue modificado en otro lugar.',
      serverSnapshot: snapshot,
    );
    final local = await _local.readByUuid(op.rabbitUuid);
    if (local != null) {
      await _local.upsert(
        local.copyWith(syncStatus: RabbitSyncStatus.conflict),
      );
    }
  }

  Future<void> _pushDelete(SyncOperation op) async {
    try {
      await _client.delete(
        '$_path${op.rabbitUuid}/',
        headers: {'Accept': 'application/json'},
      );
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
    }
    await _local.markDeleted(op.rabbitUuid, status: RabbitSyncStatus.synced);
    await _local.markOperation(id: op.id, status: SyncOpStatus.completed);
  }

  Future<void> _completeRabbit(SyncOperation op, String raw) async {
    final rabbit = Rabbit.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    await _local.upsert(rabbit.copyWith(syncStatus: RabbitSyncStatus.synced));
    await _local.markOperation(id: op.id, status: SyncOpStatus.completed);
  }

  String _errorText(ApiException e) {
    final code = e.statusCode;
    if (code != null) return 'Error $code: ${e.message}';
    return e.message;
  }
}

String snapshotJsonFrom409(ApiException error) {
  try {
    final decoded = jsonDecode(error.message);
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
