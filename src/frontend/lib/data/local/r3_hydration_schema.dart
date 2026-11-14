part of 'app_database.dart';

const _r3ReconciliationSchema = [
  '''CREATE TABLE r3_remote_bases (
    owner_id INTEGER NOT NULL, entity TEXT NOT NULL, remote_id TEXT NOT NULL,
    local_uuid TEXT NOT NULL, remote_version INTEGER NOT NULL, payload TEXT NOT NULL,
    snapshot_uuid TEXT NOT NULL,
    PRIMARY KEY(owner_id,entity,remote_id), UNIQUE(owner_id,entity,local_uuid)
  )''',
  '''CREATE TABLE r3_conflicts (
    owner_id INTEGER NOT NULL, uuid TEXT NOT NULL, entity TEXT NOT NULL,
    remote_id TEXT NOT NULL, local_uuid TEXT, snapshot_uuid TEXT NOT NULL,
    base TEXT, local TEXT, remote TEXT NOT NULL, local_version INTEGER,
    remote_version INTEGER NOT NULL, operation_uuid TEXT, reason TEXT NOT NULL,
    detected_at TEXT NOT NULL, state TEXT NOT NULL, decision TEXT,
    resolved_at TEXT, successor_uuid TEXT,
    PRIMARY KEY(owner_id,uuid),
    UNIQUE(owner_id,entity,remote_id,snapshot_uuid)
  )''',
  'ALTER TABLE r3_hydrations ADD COLUMN applied_at TEXT',
];

const _r3HydrationSchema = [
  '''ALTER TABLE sync_identity_mappings ADD COLUMN cycle_uuid TEXT''',
  '''CREATE UNIQUE INDEX r3_mapping_cycle ON sync_identity_mappings(owner_id, cycle_uuid)''',
  '''CREATE TABLE r3_hydrations (
 owner_id INTEGER NOT NULL, snapshot_uuid TEXT NOT NULL, entity TEXT NOT NULL,
 scope TEXT NOT NULL, revision INTEGER NOT NULL, cut TEXT NOT NULL,
 page_count INTEGER NOT NULL, total INTEGER NOT NULL, next_cursor INTEGER,
 received INTEGER NOT NULL DEFAULT 0, state TEXT NOT NULL,
 started_at TEXT NOT NULL, activity_at TEXT NOT NULL, completed_at TEXT, error TEXT,
 PRIMARY KEY(owner_id,snapshot_uuid)
)''',
  '''CREATE TABLE r3_hydration_pages (
 owner_id INTEGER NOT NULL, snapshot_uuid TEXT NOT NULL, page INTEGER NOT NULL,
 items TEXT NOT NULL, PRIMARY KEY(owner_id,snapshot_uuid,page)
)''',
];
