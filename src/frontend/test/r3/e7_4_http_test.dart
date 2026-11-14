import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/data/local/app_database.dart';
import 'package:frontend/data/local/r3_hydration.dart';
import 'package:frontend/data/local/r3_reconciler.dart';
import 'package:frontend/data/local/sync_evidence_store.dart';

void main() {
  test(
      'HTTP snapshots hydrate cycles and events without generating outbox writes',
      () async {
    final fixture = jsonDecode(
            File(Platform.environment['E74_HTTP_FIXTURE']!).readAsStringSync())
        as Map<String, dynamic>;
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final client = ApiClient(baseUrl: fixture['baseUrl'])
      ..accessToken = fixture['token'];
    final store = SyncEvidenceStore(db,
        ownerId: fixture['owner'], generation: 1, isCurrent: () => true);
    final hydration = R3Hydration(store, client);
    for (final entity in ['PARENT_LINK', 'REPRODUCTIVE_EVENT']) {
      final id = await hydration.open(entity, pageSize: 1);
      await hydration.resume(id);
      final reconciler = R3Reconciler(store);
      await reconciler.applySnapshot(id);
      await reconciler.applySnapshot(id);
    }
    final links = await db.select(db.localParentLinks).get();
    expect(links, hasLength(2));
    expect(links.where((row) => row.deletedAt != null), hasLength(1));
    final events = await db.select(db.localReproductiveEvents).get();
    expect(events, hasLength(1));
    expect(events.single.notes, 'Remoto');
    expect(await db.select(db.syncOperations).get(), isEmpty);
  }, skip: Platform.environment['E74_HTTP_FIXTURE'] == null);
}
