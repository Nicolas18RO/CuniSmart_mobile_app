// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $RabbitsTable extends Rabbits with TableInfo<$RabbitsTable, LocalRabbit> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RabbitsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _uuidMeta = const VerificationMeta('uuid');
  @override
  late final GeneratedColumn<String> uuid = GeneratedColumn<String>(
      'uuid', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _serverIdMeta =
      const VerificationMeta('serverId');
  @override
  late final GeneratedColumn<int> serverId = GeneratedColumn<int>(
      'server_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<int> userId = GeneratedColumn<int>(
      'user_id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _breedMeta = const VerificationMeta('breed');
  @override
  late final GeneratedColumn<String> breed = GeneratedColumn<String>(
      'breed', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sexMeta = const VerificationMeta('sex');
  @override
  late final GeneratedColumn<String> sex = GeneratedColumn<String>(
      'sex', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _birthDateMeta =
      const VerificationMeta('birthDate');
  @override
  late final GeneratedColumn<String> birthDate = GeneratedColumn<String>(
      'birth_date', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _weightMeta = const VerificationMeta('weight');
  @override
  late final GeneratedColumn<double> weight = GeneratedColumn<double>(
      'weight', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
      'notes', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
      'created_at', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _versionMeta =
      const VerificationMeta('version');
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
      'version', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _deletedAtMeta =
      const VerificationMeta('deletedAt');
  @override
  late final GeneratedColumn<String> deletedAt = GeneratedColumn<String>(
      'deleted_at', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _syncStatusMeta =
      const VerificationMeta('syncStatus');
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
      'sync_status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('SYNCED'));
  @override
  List<GeneratedColumn> get $columns => [
        uuid,
        serverId,
        userId,
        name,
        breed,
        sex,
        birthDate,
        weight,
        status,
        notes,
        createdAt,
        updatedAt,
        version,
        deletedAt,
        syncStatus
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'rabbits';
  @override
  VerificationContext validateIntegrity(Insertable<LocalRabbit> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('uuid')) {
      context.handle(
          _uuidMeta, uuid.isAcceptableOrUnknown(data['uuid']!, _uuidMeta));
    } else if (isInserting) {
      context.missing(_uuidMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(_serverIdMeta,
          serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta));
    }
    if (data.containsKey('user_id')) {
      context.handle(_userIdMeta,
          userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta));
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('breed')) {
      context.handle(
          _breedMeta, breed.isAcceptableOrUnknown(data['breed']!, _breedMeta));
    } else if (isInserting) {
      context.missing(_breedMeta);
    }
    if (data.containsKey('sex')) {
      context.handle(
          _sexMeta, sex.isAcceptableOrUnknown(data['sex']!, _sexMeta));
    } else if (isInserting) {
      context.missing(_sexMeta);
    }
    if (data.containsKey('birth_date')) {
      context.handle(_birthDateMeta,
          birthDate.isAcceptableOrUnknown(data['birth_date']!, _birthDateMeta));
    } else if (isInserting) {
      context.missing(_birthDateMeta);
    }
    if (data.containsKey('weight')) {
      context.handle(_weightMeta,
          weight.isAcceptableOrUnknown(data['weight']!, _weightMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
          _notesMeta, notes.isAcceptableOrUnknown(data['notes']!, _notesMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('version')) {
      context.handle(_versionMeta,
          version.isAcceptableOrUnknown(data['version']!, _versionMeta));
    }
    if (data.containsKey('deleted_at')) {
      context.handle(_deletedAtMeta,
          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
    }
    if (data.containsKey('sync_status')) {
      context.handle(
          _syncStatusMeta,
          syncStatus.isAcceptableOrUnknown(
              data['sync_status']!, _syncStatusMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {uuid};
  @override
  LocalRabbit map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalRabbit(
      uuid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}uuid'])!,
      serverId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}server_id']),
      userId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}user_id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      breed: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}breed'])!,
      sex: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sex'])!,
      birthDate: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}birth_date'])!,
      weight: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}weight']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      notes: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}notes'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}updated_at'])!,
      version: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}version'])!,
      deletedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}deleted_at']),
      syncStatus: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sync_status'])!,
    );
  }

  @override
  $RabbitsTable createAlias(String alias) {
    return $RabbitsTable(attachedDatabase, alias);
  }
}

class LocalRabbit extends DataClass implements Insertable<LocalRabbit> {
  final String uuid;
  final int? serverId;
  final int userId;
  final String name;
  final String breed;
  final String sex;
  final String birthDate;
  final double? weight;
  final String status;
  final String notes;
  final String createdAt;
  final String updatedAt;
  final int version;
  final String? deletedAt;
  final String syncStatus;
  const LocalRabbit(
      {required this.uuid,
      this.serverId,
      required this.userId,
      required this.name,
      required this.breed,
      required this.sex,
      required this.birthDate,
      this.weight,
      required this.status,
      required this.notes,
      required this.createdAt,
      required this.updatedAt,
      required this.version,
      this.deletedAt,
      required this.syncStatus});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['uuid'] = Variable<String>(uuid);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<int>(serverId);
    }
    map['user_id'] = Variable<int>(userId);
    map['name'] = Variable<String>(name);
    map['breed'] = Variable<String>(breed);
    map['sex'] = Variable<String>(sex);
    map['birth_date'] = Variable<String>(birthDate);
    if (!nullToAbsent || weight != null) {
      map['weight'] = Variable<double>(weight);
    }
    map['status'] = Variable<String>(status);
    map['notes'] = Variable<String>(notes);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    map['version'] = Variable<int>(version);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<String>(deletedAt);
    }
    map['sync_status'] = Variable<String>(syncStatus);
    return map;
  }

  RabbitsCompanion toCompanion(bool nullToAbsent) {
    return RabbitsCompanion(
      uuid: Value(uuid),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      userId: Value(userId),
      name: Value(name),
      breed: Value(breed),
      sex: Value(sex),
      birthDate: Value(birthDate),
      weight:
          weight == null && nullToAbsent ? const Value.absent() : Value(weight),
      status: Value(status),
      notes: Value(notes),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      version: Value(version),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncStatus: Value(syncStatus),
    );
  }

  factory LocalRabbit.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalRabbit(
      uuid: serializer.fromJson<String>(json['uuid']),
      serverId: serializer.fromJson<int?>(json['serverId']),
      userId: serializer.fromJson<int>(json['userId']),
      name: serializer.fromJson<String>(json['name']),
      breed: serializer.fromJson<String>(json['breed']),
      sex: serializer.fromJson<String>(json['sex']),
      birthDate: serializer.fromJson<String>(json['birthDate']),
      weight: serializer.fromJson<double?>(json['weight']),
      status: serializer.fromJson<String>(json['status']),
      notes: serializer.fromJson<String>(json['notes']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
      version: serializer.fromJson<int>(json['version']),
      deletedAt: serializer.fromJson<String?>(json['deletedAt']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'uuid': serializer.toJson<String>(uuid),
      'serverId': serializer.toJson<int?>(serverId),
      'userId': serializer.toJson<int>(userId),
      'name': serializer.toJson<String>(name),
      'breed': serializer.toJson<String>(breed),
      'sex': serializer.toJson<String>(sex),
      'birthDate': serializer.toJson<String>(birthDate),
      'weight': serializer.toJson<double?>(weight),
      'status': serializer.toJson<String>(status),
      'notes': serializer.toJson<String>(notes),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
      'version': serializer.toJson<int>(version),
      'deletedAt': serializer.toJson<String?>(deletedAt),
      'syncStatus': serializer.toJson<String>(syncStatus),
    };
  }

  LocalRabbit copyWith(
          {String? uuid,
          Value<int?> serverId = const Value.absent(),
          int? userId,
          String? name,
          String? breed,
          String? sex,
          String? birthDate,
          Value<double?> weight = const Value.absent(),
          String? status,
          String? notes,
          String? createdAt,
          String? updatedAt,
          int? version,
          Value<String?> deletedAt = const Value.absent(),
          String? syncStatus}) =>
      LocalRabbit(
        uuid: uuid ?? this.uuid,
        serverId: serverId.present ? serverId.value : this.serverId,
        userId: userId ?? this.userId,
        name: name ?? this.name,
        breed: breed ?? this.breed,
        sex: sex ?? this.sex,
        birthDate: birthDate ?? this.birthDate,
        weight: weight.present ? weight.value : this.weight,
        status: status ?? this.status,
        notes: notes ?? this.notes,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        version: version ?? this.version,
        deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
        syncStatus: syncStatus ?? this.syncStatus,
      );
  LocalRabbit copyWithCompanion(RabbitsCompanion data) {
    return LocalRabbit(
      uuid: data.uuid.present ? data.uuid.value : this.uuid,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      userId: data.userId.present ? data.userId.value : this.userId,
      name: data.name.present ? data.name.value : this.name,
      breed: data.breed.present ? data.breed.value : this.breed,
      sex: data.sex.present ? data.sex.value : this.sex,
      birthDate: data.birthDate.present ? data.birthDate.value : this.birthDate,
      weight: data.weight.present ? data.weight.value : this.weight,
      status: data.status.present ? data.status.value : this.status,
      notes: data.notes.present ? data.notes.value : this.notes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      version: data.version.present ? data.version.value : this.version,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncStatus:
          data.syncStatus.present ? data.syncStatus.value : this.syncStatus,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalRabbit(')
          ..write('uuid: $uuid, ')
          ..write('serverId: $serverId, ')
          ..write('userId: $userId, ')
          ..write('name: $name, ')
          ..write('breed: $breed, ')
          ..write('sex: $sex, ')
          ..write('birthDate: $birthDate, ')
          ..write('weight: $weight, ')
          ..write('status: $status, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      uuid,
      serverId,
      userId,
      name,
      breed,
      sex,
      birthDate,
      weight,
      status,
      notes,
      createdAt,
      updatedAt,
      version,
      deletedAt,
      syncStatus);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalRabbit &&
          other.uuid == this.uuid &&
          other.serverId == this.serverId &&
          other.userId == this.userId &&
          other.name == this.name &&
          other.breed == this.breed &&
          other.sex == this.sex &&
          other.birthDate == this.birthDate &&
          other.weight == this.weight &&
          other.status == this.status &&
          other.notes == this.notes &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.version == this.version &&
          other.deletedAt == this.deletedAt &&
          other.syncStatus == this.syncStatus);
}

class RabbitsCompanion extends UpdateCompanion<LocalRabbit> {
  final Value<String> uuid;
  final Value<int?> serverId;
  final Value<int> userId;
  final Value<String> name;
  final Value<String> breed;
  final Value<String> sex;
  final Value<String> birthDate;
  final Value<double?> weight;
  final Value<String> status;
  final Value<String> notes;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> version;
  final Value<String?> deletedAt;
  final Value<String> syncStatus;
  final Value<int> rowid;
  const RabbitsCompanion({
    this.uuid = const Value.absent(),
    this.serverId = const Value.absent(),
    this.userId = const Value.absent(),
    this.name = const Value.absent(),
    this.breed = const Value.absent(),
    this.sex = const Value.absent(),
    this.birthDate = const Value.absent(),
    this.weight = const Value.absent(),
    this.status = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RabbitsCompanion.insert({
    required String uuid,
    this.serverId = const Value.absent(),
    required int userId,
    required String name,
    required String breed,
    required String sex,
    required String birthDate,
    this.weight = const Value.absent(),
    required String status,
    this.notes = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.version = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : uuid = Value(uuid),
        userId = Value(userId),
        name = Value(name),
        breed = Value(breed),
        sex = Value(sex),
        birthDate = Value(birthDate),
        status = Value(status),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<LocalRabbit> custom({
    Expression<String>? uuid,
    Expression<int>? serverId,
    Expression<int>? userId,
    Expression<String>? name,
    Expression<String>? breed,
    Expression<String>? sex,
    Expression<String>? birthDate,
    Expression<double>? weight,
    Expression<String>? status,
    Expression<String>? notes,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? version,
    Expression<String>? deletedAt,
    Expression<String>? syncStatus,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (uuid != null) 'uuid': uuid,
      if (serverId != null) 'server_id': serverId,
      if (userId != null) 'user_id': userId,
      if (name != null) 'name': name,
      if (breed != null) 'breed': breed,
      if (sex != null) 'sex': sex,
      if (birthDate != null) 'birth_date': birthDate,
      if (weight != null) 'weight': weight,
      if (status != null) 'status': status,
      if (notes != null) 'notes': notes,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (version != null) 'version': version,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RabbitsCompanion copyWith(
      {Value<String>? uuid,
      Value<int?>? serverId,
      Value<int>? userId,
      Value<String>? name,
      Value<String>? breed,
      Value<String>? sex,
      Value<String>? birthDate,
      Value<double?>? weight,
      Value<String>? status,
      Value<String>? notes,
      Value<String>? createdAt,
      Value<String>? updatedAt,
      Value<int>? version,
      Value<String?>? deletedAt,
      Value<String>? syncStatus,
      Value<int>? rowid}) {
    return RabbitsCompanion(
      uuid: uuid ?? this.uuid,
      serverId: serverId ?? this.serverId,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      breed: breed ?? this.breed,
      sex: sex ?? this.sex,
      birthDate: birthDate ?? this.birthDate,
      weight: weight ?? this.weight,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (uuid.present) {
      map['uuid'] = Variable<String>(uuid.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<int>(serverId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<int>(userId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (breed.present) {
      map['breed'] = Variable<String>(breed.value);
    }
    if (sex.present) {
      map['sex'] = Variable<String>(sex.value);
    }
    if (birthDate.present) {
      map['birth_date'] = Variable<String>(birthDate.value);
    }
    if (weight.present) {
      map['weight'] = Variable<double>(weight.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(deletedAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RabbitsCompanion(')
          ..write('uuid: $uuid, ')
          ..write('serverId: $serverId, ')
          ..write('userId: $userId, ')
          ..write('name: $name, ')
          ..write('breed: $breed, ')
          ..write('sex: $sex, ')
          ..write('birthDate: $birthDate, ')
          ..write('weight: $weight, ')
          ..write('status: $status, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('version: $version, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncOperationsTable extends SyncOperations
    with TableInfo<$SyncOperationsTable, LocalSyncOperation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncOperationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _rabbitUuidMeta =
      const VerificationMeta('rabbitUuid');
  @override
  late final GeneratedColumn<String> rabbitUuid = GeneratedColumn<String>(
      'rabbit_uuid', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _operationTypeMeta =
      const VerificationMeta('operationType');
  @override
  late final GeneratedColumn<String> operationType = GeneratedColumn<String>(
      'operation_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadMeta =
      const VerificationMeta('payload');
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
      'payload', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _baseVersionMeta =
      const VerificationMeta('baseVersion');
  @override
  late final GeneratedColumn<int> baseVersion = GeneratedColumn<int>(
      'base_version', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
      'created_at', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _attemptsMeta =
      const VerificationMeta('attempts');
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
      'attempts', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('PENDING'));
  static const VerificationMeta _lastErrorMeta =
      const VerificationMeta('lastError');
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
      'last_error', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _serverSnapshotMeta =
      const VerificationMeta('serverSnapshot');
  @override
  late final GeneratedColumn<String> serverSnapshot = GeneratedColumn<String>(
      'server_snapshot', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        rabbitUuid,
        operationType,
        payload,
        baseVersion,
        createdAt,
        attempts,
        status,
        lastError,
        serverSnapshot
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_operations';
  @override
  VerificationContext validateIntegrity(Insertable<LocalSyncOperation> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('rabbit_uuid')) {
      context.handle(
          _rabbitUuidMeta,
          rabbitUuid.isAcceptableOrUnknown(
              data['rabbit_uuid']!, _rabbitUuidMeta));
    } else if (isInserting) {
      context.missing(_rabbitUuidMeta);
    }
    if (data.containsKey('operation_type')) {
      context.handle(
          _operationTypeMeta,
          operationType.isAcceptableOrUnknown(
              data['operation_type']!, _operationTypeMeta));
    } else if (isInserting) {
      context.missing(_operationTypeMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta,
          payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('base_version')) {
      context.handle(
          _baseVersionMeta,
          baseVersion.isAcceptableOrUnknown(
              data['base_version']!, _baseVersionMeta));
    } else if (isInserting) {
      context.missing(_baseVersionMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(_attemptsMeta,
          attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('last_error')) {
      context.handle(_lastErrorMeta,
          lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta));
    }
    if (data.containsKey('server_snapshot')) {
      context.handle(
          _serverSnapshotMeta,
          serverSnapshot.isAcceptableOrUnknown(
              data['server_snapshot']!, _serverSnapshotMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalSyncOperation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalSyncOperation(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      rabbitUuid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}rabbit_uuid'])!,
      operationType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}operation_type'])!,
      payload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload'])!,
      baseVersion: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}base_version'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}created_at'])!,
      attempts: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}attempts'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      lastError: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}last_error']),
      serverSnapshot: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}server_snapshot']),
    );
  }

  @override
  $SyncOperationsTable createAlias(String alias) {
    return $SyncOperationsTable(attachedDatabase, alias);
  }
}

class LocalSyncOperation extends DataClass
    implements Insertable<LocalSyncOperation> {
  final int id;
  final String rabbitUuid;
  final String operationType;
  final String payload;
  final int baseVersion;
  final String createdAt;
  final int attempts;
  final String status;
  final String? lastError;
  final String? serverSnapshot;
  const LocalSyncOperation(
      {required this.id,
      required this.rabbitUuid,
      required this.operationType,
      required this.payload,
      required this.baseVersion,
      required this.createdAt,
      required this.attempts,
      required this.status,
      this.lastError,
      this.serverSnapshot});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['rabbit_uuid'] = Variable<String>(rabbitUuid);
    map['operation_type'] = Variable<String>(operationType);
    map['payload'] = Variable<String>(payload);
    map['base_version'] = Variable<int>(baseVersion);
    map['created_at'] = Variable<String>(createdAt);
    map['attempts'] = Variable<int>(attempts);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    if (!nullToAbsent || serverSnapshot != null) {
      map['server_snapshot'] = Variable<String>(serverSnapshot);
    }
    return map;
  }

  SyncOperationsCompanion toCompanion(bool nullToAbsent) {
    return SyncOperationsCompanion(
      id: Value(id),
      rabbitUuid: Value(rabbitUuid),
      operationType: Value(operationType),
      payload: Value(payload),
      baseVersion: Value(baseVersion),
      createdAt: Value(createdAt),
      attempts: Value(attempts),
      status: Value(status),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      serverSnapshot: serverSnapshot == null && nullToAbsent
          ? const Value.absent()
          : Value(serverSnapshot),
    );
  }

  factory LocalSyncOperation.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalSyncOperation(
      id: serializer.fromJson<int>(json['id']),
      rabbitUuid: serializer.fromJson<String>(json['rabbitUuid']),
      operationType: serializer.fromJson<String>(json['operationType']),
      payload: serializer.fromJson<String>(json['payload']),
      baseVersion: serializer.fromJson<int>(json['baseVersion']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      attempts: serializer.fromJson<int>(json['attempts']),
      status: serializer.fromJson<String>(json['status']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      serverSnapshot: serializer.fromJson<String?>(json['serverSnapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'rabbitUuid': serializer.toJson<String>(rabbitUuid),
      'operationType': serializer.toJson<String>(operationType),
      'payload': serializer.toJson<String>(payload),
      'baseVersion': serializer.toJson<int>(baseVersion),
      'createdAt': serializer.toJson<String>(createdAt),
      'attempts': serializer.toJson<int>(attempts),
      'status': serializer.toJson<String>(status),
      'lastError': serializer.toJson<String?>(lastError),
      'serverSnapshot': serializer.toJson<String?>(serverSnapshot),
    };
  }

  LocalSyncOperation copyWith(
          {int? id,
          String? rabbitUuid,
          String? operationType,
          String? payload,
          int? baseVersion,
          String? createdAt,
          int? attempts,
          String? status,
          Value<String?> lastError = const Value.absent(),
          Value<String?> serverSnapshot = const Value.absent()}) =>
      LocalSyncOperation(
        id: id ?? this.id,
        rabbitUuid: rabbitUuid ?? this.rabbitUuid,
        operationType: operationType ?? this.operationType,
        payload: payload ?? this.payload,
        baseVersion: baseVersion ?? this.baseVersion,
        createdAt: createdAt ?? this.createdAt,
        attempts: attempts ?? this.attempts,
        status: status ?? this.status,
        lastError: lastError.present ? lastError.value : this.lastError,
        serverSnapshot:
            serverSnapshot.present ? serverSnapshot.value : this.serverSnapshot,
      );
  LocalSyncOperation copyWithCompanion(SyncOperationsCompanion data) {
    return LocalSyncOperation(
      id: data.id.present ? data.id.value : this.id,
      rabbitUuid:
          data.rabbitUuid.present ? data.rabbitUuid.value : this.rabbitUuid,
      operationType: data.operationType.present
          ? data.operationType.value
          : this.operationType,
      payload: data.payload.present ? data.payload.value : this.payload,
      baseVersion:
          data.baseVersion.present ? data.baseVersion.value : this.baseVersion,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      status: data.status.present ? data.status.value : this.status,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      serverSnapshot: data.serverSnapshot.present
          ? data.serverSnapshot.value
          : this.serverSnapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalSyncOperation(')
          ..write('id: $id, ')
          ..write('rabbitUuid: $rabbitUuid, ')
          ..write('operationType: $operationType, ')
          ..write('payload: $payload, ')
          ..write('baseVersion: $baseVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('status: $status, ')
          ..write('lastError: $lastError, ')
          ..write('serverSnapshot: $serverSnapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, rabbitUuid, operationType, payload,
      baseVersion, createdAt, attempts, status, lastError, serverSnapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalSyncOperation &&
          other.id == this.id &&
          other.rabbitUuid == this.rabbitUuid &&
          other.operationType == this.operationType &&
          other.payload == this.payload &&
          other.baseVersion == this.baseVersion &&
          other.createdAt == this.createdAt &&
          other.attempts == this.attempts &&
          other.status == this.status &&
          other.lastError == this.lastError &&
          other.serverSnapshot == this.serverSnapshot);
}

class SyncOperationsCompanion extends UpdateCompanion<LocalSyncOperation> {
  final Value<int> id;
  final Value<String> rabbitUuid;
  final Value<String> operationType;
  final Value<String> payload;
  final Value<int> baseVersion;
  final Value<String> createdAt;
  final Value<int> attempts;
  final Value<String> status;
  final Value<String?> lastError;
  final Value<String?> serverSnapshot;
  const SyncOperationsCompanion({
    this.id = const Value.absent(),
    this.rabbitUuid = const Value.absent(),
    this.operationType = const Value.absent(),
    this.payload = const Value.absent(),
    this.baseVersion = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.status = const Value.absent(),
    this.lastError = const Value.absent(),
    this.serverSnapshot = const Value.absent(),
  });
  SyncOperationsCompanion.insert({
    this.id = const Value.absent(),
    required String rabbitUuid,
    required String operationType,
    required String payload,
    required int baseVersion,
    required String createdAt,
    this.attempts = const Value.absent(),
    this.status = const Value.absent(),
    this.lastError = const Value.absent(),
    this.serverSnapshot = const Value.absent(),
  })  : rabbitUuid = Value(rabbitUuid),
        operationType = Value(operationType),
        payload = Value(payload),
        baseVersion = Value(baseVersion),
        createdAt = Value(createdAt);
  static Insertable<LocalSyncOperation> custom({
    Expression<int>? id,
    Expression<String>? rabbitUuid,
    Expression<String>? operationType,
    Expression<String>? payload,
    Expression<int>? baseVersion,
    Expression<String>? createdAt,
    Expression<int>? attempts,
    Expression<String>? status,
    Expression<String>? lastError,
    Expression<String>? serverSnapshot,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (rabbitUuid != null) 'rabbit_uuid': rabbitUuid,
      if (operationType != null) 'operation_type': operationType,
      if (payload != null) 'payload': payload,
      if (baseVersion != null) 'base_version': baseVersion,
      if (createdAt != null) 'created_at': createdAt,
      if (attempts != null) 'attempts': attempts,
      if (status != null) 'status': status,
      if (lastError != null) 'last_error': lastError,
      if (serverSnapshot != null) 'server_snapshot': serverSnapshot,
    });
  }

  SyncOperationsCompanion copyWith(
      {Value<int>? id,
      Value<String>? rabbitUuid,
      Value<String>? operationType,
      Value<String>? payload,
      Value<int>? baseVersion,
      Value<String>? createdAt,
      Value<int>? attempts,
      Value<String>? status,
      Value<String?>? lastError,
      Value<String?>? serverSnapshot}) {
    return SyncOperationsCompanion(
      id: id ?? this.id,
      rabbitUuid: rabbitUuid ?? this.rabbitUuid,
      operationType: operationType ?? this.operationType,
      payload: payload ?? this.payload,
      baseVersion: baseVersion ?? this.baseVersion,
      createdAt: createdAt ?? this.createdAt,
      attempts: attempts ?? this.attempts,
      status: status ?? this.status,
      lastError: lastError ?? this.lastError,
      serverSnapshot: serverSnapshot ?? this.serverSnapshot,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (rabbitUuid.present) {
      map['rabbit_uuid'] = Variable<String>(rabbitUuid.value);
    }
    if (operationType.present) {
      map['operation_type'] = Variable<String>(operationType.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (baseVersion.present) {
      map['base_version'] = Variable<int>(baseVersion.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (serverSnapshot.present) {
      map['server_snapshot'] = Variable<String>(serverSnapshot.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncOperationsCompanion(')
          ..write('id: $id, ')
          ..write('rabbitUuid: $rabbitUuid, ')
          ..write('operationType: $operationType, ')
          ..write('payload: $payload, ')
          ..write('baseVersion: $baseVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('status: $status, ')
          ..write('lastError: $lastError, ')
          ..write('serverSnapshot: $serverSnapshot')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $RabbitsTable rabbits = $RabbitsTable(this);
  late final $SyncOperationsTable syncOperations = $SyncOperationsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [rabbits, syncOperations];
}

typedef $$RabbitsTableCreateCompanionBuilder = RabbitsCompanion Function({
  required String uuid,
  Value<int?> serverId,
  required int userId,
  required String name,
  required String breed,
  required String sex,
  required String birthDate,
  Value<double?> weight,
  required String status,
  Value<String> notes,
  required String createdAt,
  required String updatedAt,
  Value<int> version,
  Value<String?> deletedAt,
  Value<String> syncStatus,
  Value<int> rowid,
});
typedef $$RabbitsTableUpdateCompanionBuilder = RabbitsCompanion Function({
  Value<String> uuid,
  Value<int?> serverId,
  Value<int> userId,
  Value<String> name,
  Value<String> breed,
  Value<String> sex,
  Value<String> birthDate,
  Value<double?> weight,
  Value<String> status,
  Value<String> notes,
  Value<String> createdAt,
  Value<String> updatedAt,
  Value<int> version,
  Value<String?> deletedAt,
  Value<String> syncStatus,
  Value<int> rowid,
});

class $$RabbitsTableFilterComposer
    extends Composer<_$AppDatabase, $RabbitsTable> {
  $$RabbitsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get uuid => $composableBuilder(
      column: $table.uuid, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get serverId => $composableBuilder(
      column: $table.serverId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get breed => $composableBuilder(
      column: $table.breed, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sex => $composableBuilder(
      column: $table.sex, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get birthDate => $composableBuilder(
      column: $table.birthDate, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get weight => $composableBuilder(
      column: $table.weight, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get syncStatus => $composableBuilder(
      column: $table.syncStatus, builder: (column) => ColumnFilters(column));
}

class $$RabbitsTableOrderingComposer
    extends Composer<_$AppDatabase, $RabbitsTable> {
  $$RabbitsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get uuid => $composableBuilder(
      column: $table.uuid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get serverId => $composableBuilder(
      column: $table.serverId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get breed => $composableBuilder(
      column: $table.breed, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sex => $composableBuilder(
      column: $table.sex, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get birthDate => $composableBuilder(
      column: $table.birthDate, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get weight => $composableBuilder(
      column: $table.weight, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get syncStatus => $composableBuilder(
      column: $table.syncStatus, builder: (column) => ColumnOrderings(column));
}

class $$RabbitsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RabbitsTable> {
  $$RabbitsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get uuid =>
      $composableBuilder(column: $table.uuid, builder: (column) => column);

  GeneratedColumn<int> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<int> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get breed =>
      $composableBuilder(column: $table.breed, builder: (column) => column);

  GeneratedColumn<String> get sex =>
      $composableBuilder(column: $table.sex, builder: (column) => column);

  GeneratedColumn<String> get birthDate =>
      $composableBuilder(column: $table.birthDate, builder: (column) => column);

  GeneratedColumn<double> get weight =>
      $composableBuilder(column: $table.weight, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get syncStatus => $composableBuilder(
      column: $table.syncStatus, builder: (column) => column);
}

class $$RabbitsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $RabbitsTable,
    LocalRabbit,
    $$RabbitsTableFilterComposer,
    $$RabbitsTableOrderingComposer,
    $$RabbitsTableAnnotationComposer,
    $$RabbitsTableCreateCompanionBuilder,
    $$RabbitsTableUpdateCompanionBuilder,
    (LocalRabbit, BaseReferences<_$AppDatabase, $RabbitsTable, LocalRabbit>),
    LocalRabbit,
    PrefetchHooks Function()> {
  $$RabbitsTableTableManager(_$AppDatabase db, $RabbitsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RabbitsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RabbitsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RabbitsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> uuid = const Value.absent(),
            Value<int?> serverId = const Value.absent(),
            Value<int> userId = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> breed = const Value.absent(),
            Value<String> sex = const Value.absent(),
            Value<String> birthDate = const Value.absent(),
            Value<double?> weight = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String> notes = const Value.absent(),
            Value<String> createdAt = const Value.absent(),
            Value<String> updatedAt = const Value.absent(),
            Value<int> version = const Value.absent(),
            Value<String?> deletedAt = const Value.absent(),
            Value<String> syncStatus = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RabbitsCompanion(
            uuid: uuid,
            serverId: serverId,
            userId: userId,
            name: name,
            breed: breed,
            sex: sex,
            birthDate: birthDate,
            weight: weight,
            status: status,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt,
            version: version,
            deletedAt: deletedAt,
            syncStatus: syncStatus,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String uuid,
            Value<int?> serverId = const Value.absent(),
            required int userId,
            required String name,
            required String breed,
            required String sex,
            required String birthDate,
            Value<double?> weight = const Value.absent(),
            required String status,
            Value<String> notes = const Value.absent(),
            required String createdAt,
            required String updatedAt,
            Value<int> version = const Value.absent(),
            Value<String?> deletedAt = const Value.absent(),
            Value<String> syncStatus = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RabbitsCompanion.insert(
            uuid: uuid,
            serverId: serverId,
            userId: userId,
            name: name,
            breed: breed,
            sex: sex,
            birthDate: birthDate,
            weight: weight,
            status: status,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt,
            version: version,
            deletedAt: deletedAt,
            syncStatus: syncStatus,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$RabbitsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $RabbitsTable,
    LocalRabbit,
    $$RabbitsTableFilterComposer,
    $$RabbitsTableOrderingComposer,
    $$RabbitsTableAnnotationComposer,
    $$RabbitsTableCreateCompanionBuilder,
    $$RabbitsTableUpdateCompanionBuilder,
    (LocalRabbit, BaseReferences<_$AppDatabase, $RabbitsTable, LocalRabbit>),
    LocalRabbit,
    PrefetchHooks Function()>;
typedef $$SyncOperationsTableCreateCompanionBuilder = SyncOperationsCompanion
    Function({
  Value<int> id,
  required String rabbitUuid,
  required String operationType,
  required String payload,
  required int baseVersion,
  required String createdAt,
  Value<int> attempts,
  Value<String> status,
  Value<String?> lastError,
  Value<String?> serverSnapshot,
});
typedef $$SyncOperationsTableUpdateCompanionBuilder = SyncOperationsCompanion
    Function({
  Value<int> id,
  Value<String> rabbitUuid,
  Value<String> operationType,
  Value<String> payload,
  Value<int> baseVersion,
  Value<String> createdAt,
  Value<int> attempts,
  Value<String> status,
  Value<String?> lastError,
  Value<String?> serverSnapshot,
});

class $$SyncOperationsTableFilterComposer
    extends Composer<_$AppDatabase, $SyncOperationsTable> {
  $$SyncOperationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get rabbitUuid => $composableBuilder(
      column: $table.rabbitUuid, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get operationType => $composableBuilder(
      column: $table.operationType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get baseVersion => $composableBuilder(
      column: $table.baseVersion, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get attempts => $composableBuilder(
      column: $table.attempts, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastError => $composableBuilder(
      column: $table.lastError, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get serverSnapshot => $composableBuilder(
      column: $table.serverSnapshot,
      builder: (column) => ColumnFilters(column));
}

class $$SyncOperationsTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncOperationsTable> {
  $$SyncOperationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get rabbitUuid => $composableBuilder(
      column: $table.rabbitUuid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get operationType => $composableBuilder(
      column: $table.operationType,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get baseVersion => $composableBuilder(
      column: $table.baseVersion, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get attempts => $composableBuilder(
      column: $table.attempts, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastError => $composableBuilder(
      column: $table.lastError, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get serverSnapshot => $composableBuilder(
      column: $table.serverSnapshot,
      builder: (column) => ColumnOrderings(column));
}

class $$SyncOperationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncOperationsTable> {
  $$SyncOperationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get rabbitUuid => $composableBuilder(
      column: $table.rabbitUuid, builder: (column) => column);

  GeneratedColumn<String> get operationType => $composableBuilder(
      column: $table.operationType, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get baseVersion => $composableBuilder(
      column: $table.baseVersion, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<String> get serverSnapshot => $composableBuilder(
      column: $table.serverSnapshot, builder: (column) => column);
}

class $$SyncOperationsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SyncOperationsTable,
    LocalSyncOperation,
    $$SyncOperationsTableFilterComposer,
    $$SyncOperationsTableOrderingComposer,
    $$SyncOperationsTableAnnotationComposer,
    $$SyncOperationsTableCreateCompanionBuilder,
    $$SyncOperationsTableUpdateCompanionBuilder,
    (
      LocalSyncOperation,
      BaseReferences<_$AppDatabase, $SyncOperationsTable, LocalSyncOperation>
    ),
    LocalSyncOperation,
    PrefetchHooks Function()> {
  $$SyncOperationsTableTableManager(
      _$AppDatabase db, $SyncOperationsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncOperationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncOperationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncOperationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> rabbitUuid = const Value.absent(),
            Value<String> operationType = const Value.absent(),
            Value<String> payload = const Value.absent(),
            Value<int> baseVersion = const Value.absent(),
            Value<String> createdAt = const Value.absent(),
            Value<int> attempts = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String?> lastError = const Value.absent(),
            Value<String?> serverSnapshot = const Value.absent(),
          }) =>
              SyncOperationsCompanion(
            id: id,
            rabbitUuid: rabbitUuid,
            operationType: operationType,
            payload: payload,
            baseVersion: baseVersion,
            createdAt: createdAt,
            attempts: attempts,
            status: status,
            lastError: lastError,
            serverSnapshot: serverSnapshot,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String rabbitUuid,
            required String operationType,
            required String payload,
            required int baseVersion,
            required String createdAt,
            Value<int> attempts = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String?> lastError = const Value.absent(),
            Value<String?> serverSnapshot = const Value.absent(),
          }) =>
              SyncOperationsCompanion.insert(
            id: id,
            rabbitUuid: rabbitUuid,
            operationType: operationType,
            payload: payload,
            baseVersion: baseVersion,
            createdAt: createdAt,
            attempts: attempts,
            status: status,
            lastError: lastError,
            serverSnapshot: serverSnapshot,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SyncOperationsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SyncOperationsTable,
    LocalSyncOperation,
    $$SyncOperationsTableFilterComposer,
    $$SyncOperationsTableOrderingComposer,
    $$SyncOperationsTableAnnotationComposer,
    $$SyncOperationsTableCreateCompanionBuilder,
    $$SyncOperationsTableUpdateCompanionBuilder,
    (
      LocalSyncOperation,
      BaseReferences<_$AppDatabase, $SyncOperationsTable, LocalSyncOperation>
    ),
    LocalSyncOperation,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$RabbitsTableTableManager get rabbits =>
      $$RabbitsTableTableManager(_db, _db.rabbits);
  $$SyncOperationsTableTableManager get syncOperations =>
      $$SyncOperationsTableTableManager(_db, _db.syncOperations);
}
