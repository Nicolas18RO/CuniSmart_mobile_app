import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/network/api_client.dart';
import 'sync_evidence_store.dart';

const _route = '/api/r3/v1/snapshots/';
final _uuid = RegExp(r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$');

class R3Hydration {
  R3Hydration(this.store, this.client);

  final SyncEvidenceStore store;
  final ApiClient client;

  Future<String> open(String entity, {int pageSize = 100}) async {
    store.checkSession();
    final raw = await client.post(_route,
        headers: {'Content-Type': 'application/json'},
        retryOnUnauthorized: false,
        body: jsonEncode({'entity': entity, 'page_size': pageSize}));
    final page = _decode(raw);
    final scope = page['scope'];
    if (page['entity'] != entity ||
        page['page'] != 0 ||
        scope is! Map<String, dynamic> ||
        (entity == 'PARENT_LINK'
            ? scope['children'] != null ||
                jsonEncode(scope['roles']) != '["FATHER","MOTHER"]'
            : scope['from'] != null || scope['to'] != null)) {
      throw const FormatException('Unexpected R3 scope');
    }
    await stage(page);
    return page['snapshot_uuid'] as String;
  }

  Future<void> resume(String id) async {
    String? failedCursor;
    try {
      while (true) {
        final cursor = await store.scoped(() async {
          final row = await _find(id);
          if (row == null) throw StateError('Unknown R3 snapshot');
          return row.readNullable<int>('next_cursor');
        });
        if (cursor == null) return;
        failedCursor = '$cursor';
        final raw = await client.get('$_route$id/?cursor=$cursor',
            retryOnUnauthorized: false);
        final page = _decode(raw);
        if (page['snapshot_uuid'] != id || page['page'] != cursor) {
          throw const FormatException('Unexpected R3 page');
        }
        await stage(page);
      }
    } catch (error) {
      if (failedCursor != null && store.isCurrent()) {
        await store.scoped(() => store.db.customStatement("""
          UPDATE r3_hydrations SET state = ?, error = ?, activity_at = ?
          WHERE owner_id = ? AND snapshot_uuid = ? AND next_cursor IS NOT NULL
        """, [
              error is FormatException ? 'FAILED' : 'PARTIAL',
              error is FormatException ? 'invalid_page' : 'interrupted',
              DateTime.now().toUtc().toIso8601String(),
              store.ownerId,
              id
            ]));
      }
      rethrow;
    }
  }

  Future<QueryRow?> _find(String id) => store.db.customSelect(
      'SELECT * FROM r3_hydrations WHERE owner_id = ? AND snapshot_uuid = ?',
      variables: [Variable(store.ownerId), Variable(id)]).getSingleOrNull();

  Map<String, dynamic> _decode(String raw) {
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid snapshot envelope');
    }
    return value;
  }

  Future<void> stage(Map<String, dynamic> page) => store.scoped(() async {
        final id = page['snapshot_uuid'];
        final entity = page['entity'];
        final revision = page['revision'];
        final cut = page['cut'];
        final ordinal = page['page'];
        final pages = page['pages'];
        final total = page['total'];
        final next = page['next_cursor'];
        final items = page['items'];
        if (page['owner_id'] != store.ownerId ||
            id is! String ||
            !_uuid.hasMatch(id) ||
            !['PARENT_LINK', 'REPRODUCTIVE_EVENT'].contains(entity) ||
            revision is! int ||
            revision <= 0 ||
            cut is! String ||
            DateTime.tryParse(cut) == null ||
            page['scope'] is! Map<String, dynamic> ||
            ordinal is! int ||
            pages is! int ||
            ordinal < 0 ||
            ordinal >= pages ||
            total is! int ||
            total < 0 ||
            next != (ordinal + 1 < pages ? ordinal + 1 : null) ||
            items is! List ||
            items.length > 200 ||
            (next != null && items.isEmpty)) {
          throw const FormatException('Invalid snapshot envelope');
        }
        for (final item in items) {
          if (item is! Map<String, dynamic> ||
              !validR3Row(entity as String, item,
                  page['scope'] as Map<String, dynamic>)) {
            throw const FormatException('Invalid snapshot item');
          }
        }
        final db = store.db;
        final scope = jsonEncode(_ordered(page['scope']));
        final raw = jsonEncode(_ordered(items));
        final now = DateTime.now().toUtc().toIso8601String();
        var previous = await _find(id);
        if (previous == null) {
          if (ordinal != 0) throw const FormatException('Missing first page');
          await db.customStatement("""
        INSERT INTO r3_hydrations
          (owner_id,snapshot_uuid,entity,scope,revision,cut,page_count,total,next_cursor,
           state,started_at,activity_at)
        VALUES (?,?,?,?,?,?,?,?,0,'IN_PROGRESS',?,?)
      """, [
            store.ownerId,
            id,
            entity,
            scope,
            revision,
            cut,
            pages,
            total,
            now,
            now
          ]);
          previous = (await _find(id))!;
        }
        if (previous.read<String>('entity') != entity ||
            previous.read<String>('scope') != scope ||
            previous.read<String>('cut') != cut ||
            previous.read<int>('revision') != revision ||
            previous.read<int>('page_count') != pages ||
            previous.read<int>('total') != total) {
          throw const FormatException('Snapshot changed');
        }
        final duplicate = await db.customSelect("""
      SELECT items FROM r3_hydration_pages WHERE owner_id=? AND snapshot_uuid=? AND page=?
    """, variables: [
          Variable(store.ownerId),
          Variable(id),
          Variable(ordinal)
        ]).getSingleOrNull();
        if (duplicate != null) {
          if (duplicate.read<String>('items') != raw) {
            throw const FormatException('Snapshot page changed');
          }
          return;
        }
        if (previous.readNullable<int>('next_cursor') != ordinal) {
          throw const FormatException('Out-of-order snapshot page');
        }
        final received = previous.read<int>('received') + items.length;
        if (received > total || (next == null && received != total)) {
          throw const FormatException('Snapshot count mismatch');
        }
        await db.customStatement("""
      INSERT INTO r3_hydration_pages VALUES (?,?,?,?)
    """, [store.ownerId, id, ordinal, raw]);
        if (next == null) {
          final rows = await db.customSelect("""
        SELECT items FROM r3_hydration_pages WHERE owner_id=? AND snapshot_uuid=?
      """, variables: [Variable(store.ownerId), Variable(id)]).get();
          final seen = <String>{};
          for (final row in rows) {
            for (final item in jsonDecode(row.read<String>('items')) as List) {
              final identity =
                  item[entity == 'PARENT_LINK' ? 'cycle_uuid' : 'uuid'];
              if (identity is String && !seen.add(identity)) {
                throw const FormatException('Duplicate snapshot identity');
              }
            }
          }
        }
        await db.customStatement("""
      UPDATE r3_hydrations SET next_cursor=?,received=?,state=?,activity_at=?,
        completed_at=?,error=NULL WHERE owner_id=? AND snapshot_uuid=?
    """, [
          next,
          received,
          next == null ? 'COMPLETE' : 'PARTIAL',
          now,
          next == null ? now : null,
          store.ownerId,
          id
        ]);
      });
}

Object? _ordered(Object? value) {
  if (value is List) return value.map(_ordered).toList();
  if (value is Map<String, dynamic>) {
    return {
      for (final key in value.keys.toList()..sort()) key: _ordered(value[key])
    };
  }
  return value;
}

bool validR3Row(
    String entity, Map<String, dynamic> row, Map<String, dynamic> scope) {
  bool uuid(Object? value) => value is String && _uuid.hasMatch(value);
  bool instant(Object? value) =>
      value is String && DateTime.tryParse(value) != null;
  final version = row['version'];
  if (version is! int ||
      version < 1 ||
      version > 2147483647 ||
      !instant(row['created_at']) ||
      !instant(row['updated_at']) ||
      (row['deleted_at'] != null && !instant(row['deleted_at']))) return false;
  if (entity == 'PARENT_LINK') {
    final child = row['child_uuid'];
    final cycle = row['cycle_uuid'];
    final created = row['creation_version'];
    final children = scope['children'];
    final roles = scope['roles'];
    return uuid(child) &&
        uuid(row['parent_uuid']) &&
        child != row['parent_uuid'] &&
        (row['role'] == 'FATHER' || row['role'] == 'MOTHER') &&
        roles is List &&
        roles.contains(row['role']) &&
        (children == null || (children is List && children.contains(child))) &&
        (cycle == null
            ? row['identity_status'] == 'UNRESOLVED' && created == null
            : uuid(cycle) &&
                row['identity_status'] == 'RESOLVED' &&
                created is int &&
                created > 0 &&
                created <= version);
  }
  final date = row['mating_date'];
  final from = scope['from'];
  final to = scope['to'];
  return uuid(row['uuid']) &&
      uuid(row['male_uuid']) &&
      uuid(row['female_uuid']) &&
      row['male_uuid'] != row['female_uuid'] &&
      row['notes'] is String &&
      date is String &&
      date.length == 10 &&
      instant(date) &&
      (from == null || (from is String && date.compareTo(from) >= 0)) &&
      (to == null || (to is String && date.compareTo(to) <= 0));
}
