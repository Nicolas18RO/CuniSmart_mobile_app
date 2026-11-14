import 'package:drift/drift.dart';

import '../core/network/api_client.dart';
import '../data/local/app_database.dart';
import '../data/local/r3_conflict_resolution.dart';
import '../data/local/r3_hydration.dart';
import '../data/local/r3_reconciler.dart';
import '../data/local/sync_evidence_store.dart';
import 'auth_service.dart';

class R3HydrationService {
  R3HydrationService(this.db, this.api, this.auth,
      {required this.onResolution});

  final AppDatabase db;
  final ApiClient api;
  final AuthService auth;
  final void Function() onResolution;
  Future<void>? _running;
  int? _runningGeneration;

  SyncEvidenceStore _scope() {
    final generation = auth.generation;
    final owner = auth.ownerId;
    if (owner == null || !auth.localDataUnlocked) {
      throw StateError('No R3 session');
    }
    return SyncEvidenceStore(db,
        ownerId: owner,
        generation: generation,
        isCurrent: () =>
            auth.ownerId == owner &&
            auth.generation == generation &&
            auth.localDataUnlocked);
  }

  Future<void> refresh() {
    final store = _scope();
    if (_running != null && _runningGeneration == store.generation) {
      return _running!;
    }
    _runningGeneration = store.generation;
    late Future<void> current;
    current = _refresh(store).whenComplete(() {
      if (identical(_running, current)) _running = null;
    });
    return _running = current;
  }

  Future<void> _refresh(SyncEvidenceStore store, {bool fresh = false}) async {
    if (await auth.verifySession() != SessionVerification.verified) {
      throw StateError('Online verification required');
    }
    store.checkSession();
    final hydration = R3Hydration(store, api);
    final reconciliation = R3Reconciler(store);
    for (final entity in ['PARENT_LINK', 'REPRODUCTIVE_EVENT']) {
      final pending = fresh
          ? null
          : await store.scoped(() => db.customSelect("""
        SELECT snapshot_uuid FROM r3_hydrations
        WHERE owner_id=? AND entity=? AND (
          state IN ('PARTIAL','IN_PROGRESS') OR (state='COMPLETE' AND applied_at IS NULL)
        ) ORDER BY revision DESC LIMIT 1
      """, variables: [
                Variable(store.ownerId),
                Variable(entity)
              ]).getSingleOrNull());
      final id = pending?.read<String>('snapshot_uuid') ??
          await hydration.open(entity);
      await hydration.resume(id);
      await reconciliation.applySnapshot(id);
    }
  }

  Future<List<QueryRow>> conflicts() async {
    final store = _scope();
    if (!await auth.canAccessLocally()) throw StateError('No R3 session');
    return R3ConflictResolution(store).open();
  }

  Future<bool> resolve(String id, R3Resolution decision,
      {String? adjustment}) async {
    final store = _scope();
    await _running;
    store.checkSession();
    await _refresh(store, fresh: true);
    store.checkSession();
    final resolved = await R3ConflictResolution(store).resolve(id, decision,
        adjustedNotes: adjustment, requireFreshObservation: true);
    if (resolved) onResolution();
    return resolved;
  }

  Future<Map<String, String>> coverage() async {
    final store = _scope();
    if (!await auth.canAccessLocally()) throw StateError('No R3 session');
    return store.scoped(() async {
      final rows = await db.customSelect('''
        SELECT entity,state FROM r3_hydrations WHERE owner_id=?
        ORDER BY revision
      ''', variables: [Variable(store.ownerId)]).get();
      return {
        'PARENT_LINK': 'NOT_STARTED',
        'REPRODUCTIVE_EVENT': 'NOT_STARTED',
        for (final row in rows)
          row.read<String>('entity'): row.read<String>('state'),
      };
    });
  }
}
