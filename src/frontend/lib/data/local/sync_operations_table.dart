import 'package:drift/drift.dart';

@DataClassName('LocalSyncOperation')
class SyncOperations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get ownerId => integer().nullable()();
  TextColumn get operationUuid => text().nullable()();
  TextColumn get entityType => text().withDefault(const Constant('RABBIT'))();
  TextColumn get dependencies => text().withDefault(const Constant('[]'))();
  TextColumn get entityReferences => text().withDefault(const Constant('[]'))();
  TextColumn get quarantineReason => text().nullable()();
  TextColumn get rabbitUuid => text()();
  TextColumn get operationType => text()();
  TextColumn get payload => text()();
  IntColumn get baseVersion => integer()();
  TextColumn get createdAt => text()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('PENDING'))();
  TextColumn get lastError => text().nullable()();
  TextColumn get serverSnapshot => text().nullable()();
}
