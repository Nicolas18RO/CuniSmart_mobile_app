import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/data/local/app_database.dart';
import 'package:frontend/data/local/r3_hydration.dart';
import 'package:frontend/data/local/r3_conflict_resolution.dart';
import 'package:frontend/data/local/r3_reconciler.dart';
import 'package:frontend/data/local/sync_dependency_evaluator.dart';
import 'package:frontend/data/local/sync_evidence_store.dart';

import 'e7_4_hydration_test.dart' as fixture;

void main() {
  for (final decision in R3Resolution.values) {
    test('B/L/R preserves pending and resolves with ${decision.name}',
        () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final store = SyncEvidenceStore(db,
          ownerId: 1, generation: 1, isCurrent: () => true);
      final hydration = R3Hydration(store, ApiClient());
      final reconciler = R3Reconciler(store);
      Future<void> apply(int revision, List<Map<String, dynamic>> rows) async {
        final id =
            'aaaaaaaa-aaaa-4aaa-8aaa-${revision.toString().padLeft(12, '0')}';
        await hydration.stage(
            fixture.page(0, revision: revision, id: id, rows: rows, pages: 1));
        await reconciler.applySnapshot(id);
        await reconciler.applySnapshot(id);
      }

      await hydration.stage(fixture.page(0));
      await reconciler.applySnapshot(fixture.snapshot);
      expect(await db.select(db.localReproductiveEvents).get(), isEmpty);
      await apply(
          2, [fixture.event(fixture.first), fixture.event(fixture.second)]);
      final rows = await db.select(db.localReproductiveEvents).get();
      expect(rows, hasLength(2));
      final local = (await db
              .customSelect(
                "SELECT local_uuid FROM r3_remote_bases WHERE remote_id='${fixture.first}'",
              )
              .getSingle())
          .read<String>('local_uuid');
      await apply(
          3, [fixture.event(fixture.first, version: 2, notes: 'server')]);
      expect(
          (await reconciler.localState('REPRODUCTIVE_EVENT', local))?['notes'],
          'server');
      await db.customStatement(
          "UPDATE local_reproductive_events SET notes='local',version=3 WHERE uuid=?",
          [local]);
      await db.customStatement("""
      INSERT INTO sync_operations(owner_id,operation_uuid,entity_type,rabbit_uuid,
        operation_type,payload,base_version,created_at)
      VALUES (1,'pending','REPRODUCTIVE_EVENT',?,'UPDATE','{}',2,'then')
    """, [local]);
      await apply(
          4, [fixture.event(fixture.first, version: 2, notes: 'server')]);
      expect(
          await db.customSelect('SELECT * FROM r3_conflicts').get(), isEmpty);
      await apply(5, [
        fixture.event(fixture.first, version: 3, notes: 'newer'),
        fixture.event(fixture.second, version: 2, deleted: true)
      ]);
      expect(
          (await reconciler.localState('REPRODUCTIVE_EVENT', local))?['notes'],
          'local');
      expect((await store.operation('pending'))?.status, 'CONFLICT');
      final conflict =
          await db.customSelect('SELECT * FROM r3_conflicts').getSingle();
      expect(conflict.read<String>('base'), contains('server'));
      expect(conflict.read<String>('local'), contains('local'));
      expect(conflict.read<String>('remote'), contains('newer'));
      expect(
          (await db.select(db.localReproductiveEvents).get())
              .where((row) => row.deletedAt != null),
          hasLength(1));
      await apply(1, []);
      expect(await db.select(db.localReproductiveEvents).get(), hasLength(2));
      await apply(
          6, [fixture.event(fixture.first, version: 3, notes: 'newer')]);
      expect(await db.customSelect('SELECT * FROM r3_conflicts').get(),
          hasLength(1));
      final resolver = R3ConflictResolution(store);
      final conflictId = conflict.read<String>('uuid');
      expect(
          await resolver.resolve(conflictId, decision,
              adjustedNotes: 'revisado', requireFreshObservation: true),
          isTrue);
      expect(await resolver.resolve(conflictId, R3Resolution.remote), isFalse);
      expect((await store.operation('pending'))?.status, 'SUPERSEDED');
      final resolved =
          await db.customSelect('SELECT * FROM r3_conflicts').getSingle();
      expect(resolved.read<String>('state'),
          'RESOLVED_${decision.name.toUpperCase()}');
      if (decision == R3Resolution.remote) {
        expect(resolved.readNullable<String>('successor_uuid'), isNull);
        expect(
            (await reconciler.localState(
                'REPRODUCTIVE_EVENT', local))?['notes'],
            'newer');
        return;
      }
      final successor = resolved.read<String>('successor_uuid');
      expect(await store.originOf(successor), 'pending');
      await db.customStatement("""
      INSERT INTO sync_operations(owner_id,operation_uuid,entity_type,rabbit_uuid,
        operation_type,payload,base_version,created_at,dependencies)
      VALUES (1,'dependent','REPRODUCTIVE_EVENT',?,'DELETE','{}',3,'then','["pending"]')
    """, [local]);
      final evaluator = SyncDependencyEvaluator(store);
      expect(
          (await evaluator.evaluate()).blocked['dependent'], SyncBlock.waiting);
      final claim = (await store.claim(successor))!;
      expect(
          await store.apply(claim,
              remoteReceipt: 'receipt',
              statusCode: 200,
              confirmedAt: fixture.instant,
              remoteEntityUuid: fixture.first,
              remoteVersion: 4),
          isTrue);
      expect((await evaluator.evaluate()).eligible, contains('dependent'));
      expect(await store.frozenCommand(successor),
          contains('"expectedVersion":3'));
      expect(
          (await reconciler.localState('REPRODUCTIVE_EVENT', local))?['notes'],
          decision == R3Resolution.manual ? 'revisado' : 'local');
    });
  }
}
