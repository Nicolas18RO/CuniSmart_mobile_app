import 'dart:convert';

import 'package:drift/drift.dart';

import '../../models/local_uuid.dart';
import 'app_database.dart';
import 'sync_command.dart';

typedef FrozenAttempt = ({
  int ownerId,
  int generation,
  String operationUuid,
  String attemptUuid,
  String command,
  String requestHash,
});

class SyncEvidenceStore {
  static final _processUuid = newLocalUuid();
  SyncEvidenceStore(
    this.db, {
    required this.ownerId,
    required this.generation,
    required this.isCurrent,
  });

  final AppDatabase db;
  final int ownerId;
  final int generation;
  final bool Function() isCurrent;

  Future<T> scoped<T>(Future<T> Function() action) => db.transaction(() async {
        checkSession();
        final result = await action();
        checkSession();
        return result;
      });

  void checkSession() {
    if (ownerId <= 0 || !isCurrent()) throw StateError('Sync scope expired');
  }

  Future<LocalSyncOperation?> operation(String uuid) async {
    checkSession();
    final result = await (db.select(db.syncOperations)
          ..where((t) =>
              t.ownerId.equals(ownerId) &
              t.operationUuid.equals(uuid) &
              t.quarantineReason.isNull()))
        .getSingleOrNull();
    checkSession();
    return result;
  }

  Future<QueryRow?> _frozen(String uuid) => db.customSelect(
      'SELECT * FROM sync_frozen_commands WHERE owner_id = ? AND operation_uuid = ?',
      variables: [Variable(ownerId), Variable(uuid)]).getSingleOrNull();

  Future<String?> frozenCommand(String uuid) => scoped(
      () async => (await _frozen(uuid))?.read<String>('canonical_command'));

  Future<Duration?> nextPublicationRetry() => scoped(() async {
        final now = DateTime.now().millisecondsSinceEpoch;
        final row = await db.customSelect('''
      SELECT MIN(f.retry_at) AS due
      FROM sync_frozen_commands f JOIN sync_operations o
        ON f.owner_id = o.owner_id AND f.operation_uuid = o.operation_uuid
      WHERE f.owner_id = ? AND o.status = 'SYNCING' AND o.attempts < 5
        AND o.quarantine_reason IS NULL AND f.retry_at > ?
    ''', variables: [Variable(ownerId), Variable(now)]).getSingle();
        final due = row.readNullable<int>('due');
        return due == null ? null : Duration(milliseconds: due - now);
      });

  Future<void> recordPublicationFailure(
    FrozenAttempt attempt,
    String reason, {
    DateTime? retryAt,
    bool conflict = false,
    String? snapshot,
  }) =>
      scoped(() async {
        final op = await operation(attempt.operationUuid);
        final row = await _frozen(attempt.operationUuid);
        if (op == null ||
            op.status != 'SYNCING' ||
            attempt.ownerId != ownerId ||
            attempt.generation != generation ||
            row?.readNullable<String>('attempt_uuid') != attempt.attemptUuid) {
          return;
        }
        await db.customStatement('''
      UPDATE sync_frozen_commands SET attempt_uuid = NULL,
        session_generation = NULL, process_uuid = NULL, retry_at = ?
      WHERE owner_id = ? AND operation_uuid = ?
    ''', [retryAt?.millisecondsSinceEpoch, ownerId, attempt.operationUuid]);
        await (db.update(db.syncOperations)..where((t) => t.id.equals(op.id)))
            .write(
          SyncOperationsCompanion(
            status: Value(conflict
                ? 'CONFLICT'
                : retryAt == null
                    ? 'FAILED'
                    : 'SYNCING'),
            lastError: Value(reason),
            serverSnapshot: Value(snapshot),
          ),
        );
      });

  /// Lineage is audit evidence. Only an explicit domain dependency gates send.
  Future<String> derive(
    String originalUuid, {
    String? action,
    required String destination,
    required Map<String, Object?> payload,
    int? expectedVersion,
    bool requiresOriginalResult = false,
    bool fromReconciliation = false,
  }) =>
      scoped(() async {
        final original = await operation(originalUuid);
        final frozen = await _frozen(originalUuid);
        if (original == null ||
            (frozen == null &&
                (!fromReconciliation || original.status != 'CONFLICT')) ||
            (frozen != null &&
                syncRequestHash(frozen.read<String>('canonical_command')) !=
                    frozen.read<String>('request_hash'))) {
          throw StateError('Original command is missing or invalid');
        }
        final previous = frozen == null
            ? null
            : jsonDecode(frozen.read<String>('canonical_command'));
        final derivedAction = action ?? original.operationType;
        if (derivedAction != original.operationType) {
          final mapping = await db.customSelect('''
            SELECT remote_entity_uuid, cycle_uuid
            FROM sync_identity_mappings
            WHERE owner_id=? AND entity_type=? AND local_uuid=?
          ''', variables: [
            Variable(ownerId),
            Variable(original.entityType),
            Variable(original.rabbitUuid),
          ]).getSingleOrNull();
          final remoteIdentity = original.entityType == 'PARENT_LINK'
              ? mapping?.readNullable<String>('cycle_uuid')
              : mapping?.readNullable<String>('remote_entity_uuid');
          if (remoteIdentity == null) {
            throw StateError('Cannot derive action without remote identity');
          }
        }
        if (frozen != null &&
            (previous is! Map<String, dynamic> ||
                previous['entityType'] != original.entityType ||
                (derivedAction == original.operationType &&
                    previous['destination'] != destination))) {
          throw ArgumentError('Derivation must preserve the command target');
        }
        final command = canonicalSyncCommand(
          entityType: original.entityType,
          action: derivedAction,
          destination: destination,
          payload: payload,
          expectedVersion: expectedVersion,
        );
        if (command == frozen?.read<String>('canonical_command')) {
          throw ArgumentError('Derivation requires a changed command');
        }
        final dependencies =
            (jsonDecode(original.dependencies) as List).cast<String>();
        final localPayload =
            jsonDecode(original.payload) as Map<String, dynamic>;
        for (final key in [
          'child_uuid',
          'parent_uuid',
          'role',
          'male_uuid',
          'female_uuid'
        ]) {
          if (payload.containsKey(key) &&
              payload[key] != localPayload[key] &&
              !(fromReconciliation &&
                  key == 'parent_uuid' &&
                  original.entityType == 'PARENT_LINK' &&
                  original.operationType == 'UPDATE')) {
            throw ArgumentError('Derivation must preserve entity references');
          }
        }
        final uuid = newLocalUuid();
        await db.into(db.syncOperations).insert(SyncOperationsCompanion.insert(
              ownerId: Value(ownerId),
              operationUuid: Value(uuid),
              entityType: Value(original.entityType),
              rabbitUuid: original.rabbitUuid,
              operationType: derivedAction,
              payload: jsonEncode({...localPayload, ...payload}),
              baseVersion: original.baseVersion,
              createdAt: DateTime.now().toUtc().toIso8601String(),
              entityReferences: Value(
                fromReconciliation && payload.containsKey('parent_uuid')
                    ? jsonEncode(
                        [localPayload['child_uuid'], payload['parent_uuid']])
                    : original.entityReferences,
              ),
              dependencies: Value(jsonEncode({
                ...dependencies,
                if (requiresOriginalResult) originalUuid,
              }.toList())),
            ));
        await db.customStatement('''
          INSERT INTO sync_frozen_commands
            (owner_id, operation_uuid, canonical_command, request_hash, derived_from_uuid)
          VALUES (?, ?, ?, ?, ?)
        ''', [ownerId, uuid, command, syncRequestHash(command), originalUuid]);
        return uuid;
      });

  Future<String?> originOf(String uuid) => scoped(() async =>
      (await _frozen(uuid))?.readNullable<String>('derived_from_uuid'));

  Future<bool> applyReceipt(
      FrozenAttempt attempt, Map<String, Object?> receipt) async {
    if (attempt.ownerId != ownerId ||
        attempt.generation != generation ||
        !isCurrent()) return false;
    final command = jsonDecode(attempt.command);
    if (command is! Map<String, dynamic>) return false;
    final identity = receipt['remoteIdentity'];
    final version = receipt['remoteVersion'];
    final status = receipt['statusCode'];
    final confirmed = receipt['confirmedAt'];
    final reference = receipt['receiptId'];
    final hasBody = receipt['bodyPresent'];
    final body = receipt['responseBody'];
    if (receipt['ownerId'] != ownerId ||
        receipt['operationUuid'] != attempt.operationUuid ||
        receipt['requestHash'] != attempt.requestHash ||
        receipt['entityType'] != command['entityType'] ||
        receipt['action'] != command['action'] ||
        receipt['contractVersion'] != command['version'] ||
        identity is! Map<String, dynamic> ||
        version is! int ||
        version < 1 ||
        status is! int ||
        status < 200 ||
        status > 299 ||
        confirmed is! String ||
        DateTime.tryParse(confirmed) == null ||
        reference is! int ||
        reference < 1 ||
        hasBody is! bool ||
        (!hasBody && body != null) ||
        (status == 204 && hasBody)) {
      return false;
    }
    final isParent = command['entityType'] == 'PARENT_LINK';
    final remoteUuid = identity['uuid'];
    final child = identity['childUuid'];
    final role = identity['role'];
    final cycle = identity['cycleUuid'];
    final uuidPattern =
        RegExp(r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$');
    if (isParent
        ? remoteUuid != null ||
            child is! String ||
            !uuidPattern.hasMatch(child) ||
            (role != 'FATHER' && role != 'MOTHER') ||
            (cycle is! String || !uuidPattern.hasMatch(cycle))
        : remoteUuid is! String || !uuidPattern.hasMatch(remoteUuid)) {
      return false;
    }
    final payload = command['payload'];
    if (payload is! Map<String, dynamic>) return false;
    if (isParent) {
      if (cycle != null && (cycle is! String || !uuidPattern.hasMatch(cycle))) {
        return false;
      }
      final destination = command['destination'];
      if (destination is! String) return false;
      final matches = destination.startsWith('/api/')
          ? destination == '/api/rabbits/$child/parents/$role/'
          : child == payload['child_uuid'] && role == payload['role'];
      if (!matches) return false;
    }
    if (!isParent &&
        command['action'] != 'CREATE' &&
        command['destination'] != '/api/reproductive-events/$remoteUuid/') {
      return false;
    }
    return apply(
      attempt,
      remoteReceipt: reference.toString(),
      statusCode: status,
      confirmedAt: confirmed,
      responseJson: hasBody ? jsonEncode(body) : null,
      remoteEntityUuid: isParent ? null : remoteUuid as String,
      remoteVersion: version,
      childUuid: isParent ? child as String : null,
      role: isParent ? role as String : null,
      creationVersion: isParent ? version : null,
      cycleUuid: isParent ? cycle as String? : null,
      receiptEntity: receipt['entityType'] as String,
      receiptAction: receipt['action'] as String,
    );
  }

  Future<void> freeze(String uuid, String command, String hash) =>
      scoped(() async {
        if (command.isEmpty || hash != syncRequestHash(command)) {
          throw ArgumentError('Invalid frozen command');
        }
        final op = await operation(uuid);
        if (op == null || op.entityType == 'RABBIT' || op.status != 'PENDING') {
          throw StateError('Operation cannot be frozen');
        }
        final existing = await _frozen(uuid);
        if (existing == null) {
          await db.customStatement('''
        INSERT INTO sync_frozen_commands
          (owner_id, operation_uuid, canonical_command, request_hash)
        VALUES (?, ?, ?, ?)
      ''', [ownerId, uuid, command, hash]);
        } else if (existing.read<String>('canonical_command') != command ||
            existing.read<String>('request_hash') != hash) {
          throw StateError('Frozen command requires a new operation');
        }
      });

  Future<FrozenAttempt?> claim(
    String uuid, {
    bool recovering = false,
    bool publication = false,
  }) =>
      scoped(() async {
        final op = await operation(uuid);
        final expected = recovering ? 'SYNCING' : 'PENDING';
        if (op == null || op.entityType == 'RABBIT' || op.status != expected) {
          return null;
        }
        final row = await _frozen(uuid);
        if (recovering && row != null) {
          final confirmed = await db.customSelect('''
            SELECT request_hash FROM sync_operation_results
            WHERE owner_id = ? AND operation_uuid = ?
          ''',
              variables: [Variable(ownerId), Variable(uuid)]).getSingleOrNull();
          if (confirmed != null) {
            if (confirmed.read<String>('request_hash') ==
                row.read<String>('request_hash')) {
              await (db.update(db.syncOperations)
                    ..where((t) => t.id.equals(op.id)))
                  .write(const SyncOperationsCompanion(
                      status: Value('COMPLETED')));
            }
            return null;
          }
        }
        if (row == null) return null;
        final retryAt = row.readNullable<int>('retry_at');
        if (publication &&
            (op.attempts >= 5 ||
                (retryAt != null &&
                    retryAt > DateTime.now().millisecondsSinceEpoch))) {
          return null;
        }
        final active = row.readNullable<String>('attempt_uuid');
        final priorGeneration = row.readNullable<int>('session_generation');
        final sameContext = priorGeneration == generation &&
            row.readNullable<String>('process_uuid') == _processUuid;
        if (active != null && (!recovering || sameContext)) {
          return null;
        }
        final token = newLocalUuid();
        await db.customStatement('''
      UPDATE sync_frozen_commands
      SET attempt_uuid = ?, session_generation = ?, process_uuid = ?
      WHERE owner_id = ? AND operation_uuid = ?
    ''', [token, generation, _processUuid, ownerId, uuid]);
        await (db.update(db.syncOperations)..where((t) => t.id.equals(op.id)))
            .write(SyncOperationsCompanion(
          status: const Value('SYNCING'),
          attempts: publication ? Value(op.attempts + 1) : const Value.absent(),
        ));
        return (
          ownerId: ownerId,
          generation: generation,
          operationUuid: uuid,
          attemptUuid: token,
          command: row.read<String>('canonical_command'),
          requestHash: row.read<String>('request_hash'),
        );
      });

  Future<bool> apply(
    FrozenAttempt attempt, {
    required String remoteReceipt,
    required int statusCode,
    required String confirmedAt,
    String? responseJson,
    String? remoteEntityUuid,
    int? remoteVersion,
    String? childUuid,
    String? role,
    int? creationVersion,
    String? cycleUuid,
    String? receiptEntity,
    String? receiptAction,
  }) async {
    if (attempt.ownerId != ownerId ||
        attempt.generation != generation ||
        !isCurrent()) return false;
    return scoped(() async {
      final uuid = attempt.operationUuid;
      final op = await operation(uuid);
      final row = await _frozen(uuid);
      if (op == null ||
          op.status != 'SYNCING' ||
          row?.readNullable<String>('attempt_uuid') != attempt.attemptUuid ||
          row?.readNullable<int>('session_generation') != generation ||
          row?.readNullable<String>('process_uuid') != _processUuid ||
          row?.read<String>('request_hash') != attempt.requestHash ||
          row?.read<String>('canonical_command') != attempt.command ||
          (receiptEntity != null && op.entityType != receiptEntity) ||
          (receiptAction != null && op.operationType != receiptAction)) {
        return false;
      }
      if (remoteReceipt.isEmpty) throw ArgumentError('Missing receipt');
      if (op.entityType == 'PARENT_LINK' &&
          op.operationType != 'CREATE' &&
          cycleUuid != null) {
        final mapping = await db.customSelect('''
          SELECT cycle_uuid FROM sync_identity_mappings
          WHERE owner_id=? AND entity_type='PARENT_LINK' AND local_uuid=?
        ''', variables: [
          Variable(ownerId),
          Variable(op.rabbitUuid)
        ]).getSingleOrNull();
        if (mapping?.readNullable<String>('cycle_uuid') != cycleUuid)
          return false;
      }
      if (op.operationType == 'CREATE') {
        await db.customStatement('''
          INSERT INTO sync_identity_mappings
            (owner_id, entity_type, local_uuid, remote_entity_uuid,
             child_uuid, role, creation_version, cycle_uuid)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''', [
          ownerId,
          op.entityType,
          op.rabbitUuid,
          remoteEntityUuid,
          childUuid,
          role,
          creationVersion,
          cycleUuid,
        ]);
      }
      await db.customStatement('''
        INSERT INTO sync_operation_results
          (owner_id, operation_uuid, request_hash, remote_receipt, status_code,
           response_json, remote_entity_uuid, remote_version, confirmed_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''', [
        ownerId,
        uuid,
        attempt.requestHash,
        remoteReceipt,
        statusCode,
        responseJson,
        remoteEntityUuid,
        remoteVersion,
        confirmedAt
      ]);
      await (db.update(db.syncOperations)..where((t) => t.id.equals(op.id)))
          .write(const SyncOperationsCompanion(status: Value('COMPLETED')));
      return true;
    });
  }
}
