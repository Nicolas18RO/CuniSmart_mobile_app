enum SyncOperationType {
  create,
  update,
  delete;

  String get storageValue => switch (this) {
        create => 'CREATE',
        update => 'UPDATE',
        delete => 'DELETE',
      };

  static SyncOperationType fromStorage(String raw) {
    return switch (raw) {
      'UPDATE' => update,
      'DELETE' => delete,
      _ => create,
    };
  }
}

enum SyncOpStatus {
  pending,
  syncing,
  completed,
  failed,
  conflict;

  String get storageValue => switch (this) {
        pending => 'PENDING',
        syncing => 'SYNCING',
        completed => 'COMPLETED',
        failed => 'FAILED',
        conflict => 'CONFLICT',
      };

  static SyncOpStatus fromStorage(String raw) {
    return switch (raw) {
      'SYNCING' => syncing,
      'COMPLETED' => completed,
      'FAILED' => failed,
      'CONFLICT' => conflict,
      _ => pending,
    };
  }
}

class SyncOperation {
  const SyncOperation({
    required this.id,
    required this.rabbitUuid,
    required this.operationType,
    required this.payload,
    required this.baseVersion,
    required this.createdAt,
    required this.attempts,
    required this.status,
    this.lastError,
    this.serverSnapshot,
  });

  final int id;
  final String rabbitUuid;
  final SyncOperationType operationType;
  final String payload;
  final int baseVersion;
  final String createdAt;
  final int attempts;
  final SyncOpStatus status;
  final String? lastError;
  final String? serverSnapshot;
}
