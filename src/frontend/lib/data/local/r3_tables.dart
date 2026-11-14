import 'package:drift/drift.dart';

@DataClassName('StoredParentLink')
class LocalParentLinks extends Table {
  TextColumn get uuid => text()();
  IntColumn get ownerId => integer()();
  TextColumn get childUuid => text()();
  TextColumn get parentUuid => text()();
  TextColumn get role => text()();
  IntColumn get version => integer()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
  TextColumn get deletedAt => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {uuid};

  @override
  List<String> get customConstraints => [
        'CHECK (owner_id > 0)',
        'CHECK (child_uuid <> parent_uuid)',
        "CHECK (role IN ('FATHER', 'MOTHER'))",
        'CHECK (version BETWEEN 1 AND 2147483647)',
      ];
}

@DataClassName('StoredReproductiveEvent')
class LocalReproductiveEvents extends Table {
  TextColumn get uuid => text()();
  IntColumn get ownerId => integer()();
  TextColumn get maleUuid => text()();
  TextColumn get femaleUuid => text()();
  TextColumn get matingDate => text()();
  TextColumn get notes => text()();
  IntColumn get version => integer()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
  TextColumn get deletedAt => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {uuid};

  @override
  List<String> get customConstraints => [
        'CHECK (owner_id > 0)',
        'CHECK (male_uuid <> female_uuid)',
        'CHECK (version BETWEEN 1 AND 2147483647)',
      ];
}
