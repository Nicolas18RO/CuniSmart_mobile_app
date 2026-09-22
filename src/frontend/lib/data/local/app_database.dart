import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'rabbits_table.dart';
import 'sync_operations_table.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Rabbits, SyncOperations])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  factory AppDatabase.memory() => AppDatabase(NativeDatabase.memory());

  factory AppDatabase.file(File file) => AppDatabase(NativeDatabase(file));

  factory AppDatabase.fromDocuments() {
    return AppDatabase(LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'cunismart.sqlite'));
      return NativeDatabase.createInBackground(file);
    }));
  }

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(syncOperations);
          }
        },
      );
}
