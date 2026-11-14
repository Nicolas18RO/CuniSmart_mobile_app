part of 'app_database.dart';

const _e72Schema = [
  """
  CREATE TABLE sync_frozen_commands (
    owner_id INTEGER NOT NULL CHECK (owner_id > 0),
    operation_uuid TEXT NOT NULL,
    canonical_command TEXT NOT NULL,
    request_hash TEXT NOT NULL CHECK (length(request_hash) = 64),
    attempt_uuid TEXT,
    session_generation INTEGER,
    process_uuid TEXT,
    CHECK ((attempt_uuid IS NULL) = (session_generation IS NULL)),
    CHECK ((attempt_uuid IS NULL) = (process_uuid IS NULL)),
    PRIMARY KEY (owner_id, operation_uuid)
  )
  """,
  """
  CREATE TABLE sync_operation_results (
    owner_id INTEGER NOT NULL CHECK (owner_id > 0),
    operation_uuid TEXT NOT NULL,
    request_hash TEXT NOT NULL CHECK (length(request_hash) = 64),
    remote_receipt TEXT NOT NULL,
    status_code INTEGER NOT NULL CHECK (status_code BETWEEN 200 AND 299),
    response_json TEXT,
    remote_entity_uuid TEXT,
    remote_version INTEGER CHECK (remote_version > 0),
    confirmed_at TEXT NOT NULL,
    PRIMARY KEY (owner_id, operation_uuid)
  )
  """,
  """
  CREATE TABLE sync_identity_mappings (
    owner_id INTEGER NOT NULL CHECK (owner_id > 0),
    entity_type TEXT NOT NULL,
    local_uuid TEXT NOT NULL,
    remote_entity_uuid TEXT,
    child_uuid TEXT,
    role TEXT,
    creation_version INTEGER,
    PRIMARY KEY (owner_id, entity_type, local_uuid),
    UNIQUE (owner_id, entity_type, remote_entity_uuid),
    UNIQUE (owner_id, child_uuid, role, creation_version),
    CHECK (
      (entity_type = 'PARENT_LINK' AND remote_entity_uuid IS NULL
        AND child_uuid IS NOT NULL AND role IN ('FATHER', 'MOTHER')
        AND role IS NOT NULL AND creation_version IS NOT NULL AND creation_version > 0)
      OR
      (entity_type IN ('RABBIT', 'REPRODUCTIVE_EVENT')
        AND remote_entity_uuid IS NOT NULL AND child_uuid IS NULL
        AND role IS NULL AND creation_version IS NULL)
    )
  )
  """,
  """
  CREATE TABLE sync_create_cancellations (
    owner_id INTEGER NOT NULL CHECK (owner_id > 0),
    operation_uuid TEXT NOT NULL,
    rabbit_uuid TEXT NOT NULL,
    reason TEXT NOT NULL,
    cancelled_at TEXT NOT NULL,
    PRIMARY KEY (owner_id, operation_uuid)
  )
  """,
  'CREATE INDEX sync_cancelled_rabbit ON sync_create_cancellations(owner_id, rabbit_uuid)',
  """
  CREATE TABLE sync_rabbit_preimages (
    owner_id INTEGER NOT NULL,
    operation_uuid TEXT NOT NULL,
    sex TEXT NOT NULL,
    status TEXT NOT NULL,
    knowledge TEXT NOT NULL,
    PRIMARY KEY (owner_id, operation_uuid)
  )
  """,
];
