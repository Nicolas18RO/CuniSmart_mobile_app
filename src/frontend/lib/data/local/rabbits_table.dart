import 'package:drift/drift.dart';

@DataClassName('LocalRabbit')
class Rabbits extends Table {
  TextColumn get uuid => text()();
  IntColumn get serverId => integer().nullable()();
  IntColumn get userId => integer()();
  TextColumn get name => text()();
  TextColumn get breed => text()();
  TextColumn get sex => text()();
  TextColumn get birthDate => text()();
  RealColumn get weight => real().nullable()();
  TextColumn get status => text()();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deletedAt => text().nullable()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('SYNCED'))();

  @override
  Set<Column<Object>> get primaryKey => {uuid};
}
