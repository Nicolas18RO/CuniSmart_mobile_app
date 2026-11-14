import 'dart:convert';

import 'package:drift/drift.dart';

import 'app_database.dart';
import 'sync_evidence_store.dart';

enum SyncBlock {
  waiting,
  conflict,
  failed,
  cancelled,
  quarantine,
  missing,
  cycle
}

List<String>? syncIds(String raw) {
  try {
    final value = jsonDecode(raw);
    if (value is List &&
        value.every((item) => item is String && item.isNotEmpty)) {
      return value.cast<String>();
    }
  } on FormatException {
    return null;
  }
  return null;
}

class SyncDependencyEvaluator {
  const SyncDependencyEvaluator(this.store);

  final SyncEvidenceStore store;

  Future<({List<String> eligible, Map<String, SyncBlock> blocked})> evaluate(
          {bool includeRecovering = false}) =>
      store.scoped(() async {
        final db = store.db;
        final owner = store.ownerId;
        final operations = await (db.select(db.syncOperations)
              ..where((t) => t.ownerId.equals(owner))
              ..orderBy([(t) => OrderingTerm.asc(t.id)]))
            .get();
        final rabbits = await (db.select(db.rabbits)
              ..where((t) => t.userId.equals(owner)))
            .get();
        final byRabbit = {for (final rabbit in rabbits) rabbit.uuid: rabbit};
        final cancellations = await db.customSelect(
            'SELECT * FROM sync_create_cancellations WHERE owner_id = ?',
            variables: [Variable(owner)]).get();
        final cancelled =
            cancellations.map((r) => r.read<String>('operation_uuid')).toSet();
        final cancelledRabbits =
            cancellations.map((r) => r.read<String>('rabbit_uuid')).toSet();
        final results = await db.customSelect(
            'SELECT operation_uuid FROM sync_operation_results WHERE owner_id = ?',
            variables: [Variable(owner)]).get();
        final confirmed =
            results.map((r) => r.read<String>('operation_uuid')).toSet();
        final resolutions = await db.customSelect('''
          SELECT operation_uuid, successor_uuid FROM r3_conflicts
          WHERE owner_id=? AND state IN ('RESOLVED_LOCAL','RESOLVED_MANUAL')
            AND successor_uuid IS NOT NULL
        ''', variables: [Variable(owner)]).get();
        final nodes = {
          for (final row in operations)
            if (row.operationUuid != null) row.operationUuid!: row,
        };
        final fulfilled = <String>{};
        for (final resolution in resolutions) {
          final original = resolution.readNullable<String>('operation_uuid');
          final successor = resolution.read<String>('successor_uuid');
          final before = nodes[original];
          final after = nodes[successor];
          if (original != null &&
              before?.status == 'SUPERSEDED' &&
              after?.status == 'COMPLETED' &&
              after?.quarantineReason == null &&
              after?.rabbitUuid == before?.rabbitUuid &&
              after?.entityType == before?.entityType &&
              after?.operationType == before?.operationType &&
              confirmed.contains(successor)) {
            fulfilled.add(original);
          }
        }
        final deps = {
          for (final node in nodes.entries)
            node.key: syncIds(node.value.dependencies)
        };
        final blockers = <String, SyncBlock>{};
        final stack = <String>[];
        final active = <String, int>{};
        final visited = <String>{};
        final order = <String>[];

        void visit(String uuid) {
          final cycleStart = active[uuid];
          if (cycleStart != null) {
            for (final node in stack.skip(cycleStart)) {
              blockers[node] = SyncBlock.cycle;
            }
            return;
          }
          if (!visited.add(uuid)) return;
          active[uuid] = stack.length;
          stack.add(uuid);
          for (final predecessor in deps[uuid] ?? const <String>[]) {
            if (nodes.containsKey(predecessor)) visit(predecessor);
          }
          stack.removeLast();
          active.remove(uuid);
          order.add(uuid);
        }

        for (final uuid in nodes.keys) {
          visit(uuid);
        }

        final eligible = <String>[];
        for (final uuid in order) {
          final row = nodes[uuid]!;
          final dependencies = deps[uuid];
          final refs = syncIds(row.entityReferences);
          if (blockers.containsKey(uuid)) continue;
          final ownBlock = switch (row.status) {
            _ when row.quarantineReason != null => SyncBlock.quarantine,
            _ when cancelled.contains(uuid) => SyncBlock.cancelled,
            'CONFLICT' => SyncBlock.conflict,
            'FAILED' => SyncBlock.failed,
            _ when dependencies == null || refs == null => SyncBlock.missing,
            _ => null,
          };
          if (ownBlock != null) {
            blockers[uuid] = ownBlock;
            continue;
          }
          for (final predecessor in dependencies!) {
            final source = nodes[predecessor];
            final inherited = blockers[predecessor];
            final rabbit = byRabbit[source?.rabbitUuid];
            final done = source?.status == 'COMPLETED' &&
                (source!.entityType == 'RABBIT'
                    ? rabbit != null &&
                        rabbit.serverId != null &&
                        rabbit.deletedAt == null &&
                        rabbit.quarantineReason == null
                    : confirmed.contains(predecessor));
            final reason = inherited ??
                (cancelled.contains(predecessor)
                    ? SyncBlock.cancelled
                    : source == null
                        ? SyncBlock.missing
                        : done || fulfilled.contains(predecessor)
                            ? null
                            : SyncBlock.waiting);
            if (reason != null) {
              blockers[uuid] = reason;
              break;
            }
          }
          if (blockers.containsKey(uuid) ||
              row.entityType == 'RABBIT' ||
              (row.status != 'PENDING' &&
                  !(includeRecovering && row.status == 'SYNCING'))) {
            continue;
          }
          final required = requiredRabbitRoles(row);
          if (required == null ||
              required.keys.any((key) => !refs!.contains(key))) {
            blockers[uuid] = SyncBlock.missing;
            continue;
          }
          for (final entry in required.entries) {
            final rabbit = byRabbit[entry.key];
            if (rabbit == null ||
                rabbit.deletedAt != null ||
                rabbit.serverId == null ||
                rabbit.quarantineReason != null ||
                !await _confirmedRequirement(rabbit, entry.value)) {
              blockers[uuid] = rabbit?.quarantineReason != null
                  ? SyncBlock.quarantine
                  : rabbit == null && cancelledRabbits.contains(entry.key)
                      ? SyncBlock.cancelled
                      : SyncBlock.missing;
              break;
            }
          }
          if (!blockers.containsKey(uuid)) eligible.add(uuid);
        }
        // Eligible nodes have no unconfirmed predecessors and can use queue order.
        eligible.sort((a, b) => nodes[a]!.id.compareTo(nodes[b]!.id));
        return (eligible: eligible, blocked: blockers);
      });

  Future<bool> _confirmedRequirement(
      LocalRabbit rabbit, bool Function(LocalRabbit) requirement) async {
    if (rabbit.syncStatus == 'SYNCED') return requirement(rabbit);
    if (rabbit.syncStatus != 'PENDING_UPDATE' || !requirement(rabbit)) {
      return false;
    }
    final before = await store.db.customSelect('''
      SELECT p.sex, p.status, p.knowledge
      FROM sync_rabbit_preimages p JOIN sync_operations o
        ON o.owner_id = p.owner_id AND o.operation_uuid = p.operation_uuid
      WHERE p.owner_id = ? AND o.rabbit_uuid = ? AND o.entity_type = 'RABBIT'
        AND o.operation_type = 'UPDATE' AND o.quarantine_reason IS NULL
        AND o.status = 'PENDING' AND o.attempts = 0
        AND NOT EXISTS (
          SELECT 1 FROM sync_operations other
          WHERE other.owner_id = o.owner_id AND other.rabbit_uuid = o.rabbit_uuid
            AND other.entity_type = 'RABBIT' AND other.id <> o.id
            AND other.status <> 'COMPLETED'
        )
    ''', variables: [
      Variable(store.ownerId),
      Variable(rabbit.uuid)
    ]).getSingleOrNull();
    return before != null &&
        requirement(rabbit.copyWith(
          sex: before.read<String>('sex'),
          status: before.read<String>('status'),
          genealogyKnowledge: before.read<String>('knowledge'),
        ));
  }
}

Map<String, bool Function(LocalRabbit)>? requiredRabbitRoles(
    LocalSyncOperation row) {
  try {
    final payload = jsonDecode(row.payload);
    if (payload is! Map<String, dynamic>) return null;
    return rabbitRequirements(row.entityType, row.operationType, payload);
  } on FormatException {
    return null;
  }
}

Map<String, bool Function(LocalRabbit)>? rabbitRequirements(
    String entity, String action, Map<String, dynamic> payload) {
  if (entity == 'PARENT_LINK') {
    final child = payload['child_uuid'];
    if (child is! String) return null;
    if (action == 'DELETE') return {child: (_) => true};
    final parent = payload['parent_uuid'];
    final role = payload['role'];
    if (parent is! String ||
        parent == child ||
        (role != 'FATHER' && role != 'MOTHER')) {
      return null;
    }
    return {
      child: (rabbit) => rabbit.genealogyKnowledge != 'FOUNDER',
      parent: (rabbit) => rabbit.sex == (role == 'FATHER' ? 'male' : 'female'),
    };
  }
  if (entity == 'REPRODUCTIVE_EVENT') {
    if (action == 'DELETE') return {};
    final male = payload['male_uuid'];
    final female = payload['female_uuid'];
    if (male is! String || female is! String || male == female) return null;
    return {
      male: (rabbit) => rabbit.sex == 'male' && rabbit.status == 'active',
      female: (rabbit) => rabbit.sex == 'female' && rabbit.status == 'active',
    };
  }
  return null;
}
