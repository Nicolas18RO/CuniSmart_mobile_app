/// Local-only sync states. Not a Django field.
enum RabbitSyncStatus {
  synced,
  pendingCreate,
  pendingUpdate,
  pendingDelete,
  conflict;

  String get storageValue => switch (this) {
        synced => 'SYNCED',
        pendingCreate => 'PENDING_CREATE',
        pendingUpdate => 'PENDING_UPDATE',
        pendingDelete => 'PENDING_DELETE',
        conflict => 'CONFLICT',
      };

  String get label => switch (this) {
        synced => 'Sincronizado',
        pendingCreate => 'Pendiente de crear',
        pendingUpdate => 'Pendiente de actualizar',
        pendingDelete => 'Pendiente de eliminar',
        conflict => 'Conflicto',
      };

  static RabbitSyncStatus fromStorage(String raw) {
    return switch (raw) {
      'PENDING_CREATE' => pendingCreate,
      'PENDING_UPDATE' => pendingUpdate,
      'PENDING_DELETE' => pendingDelete,
      'CONFLICT' => conflict,
      _ => synced,
    };
  }
}
