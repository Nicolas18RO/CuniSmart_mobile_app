import 'sync_status.dart';

/// Matches Django `core.Rabbit` + DRF JSON shape, plus local sync fields.
class Rabbit {
  const Rabbit({
    required this.id,
    required this.uuid,
    this.userId = 0,
    required this.name,
    required this.breed,
    required this.sex,
    required this.birthDate,
    this.weight,
    required this.status,
    required this.notes,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.syncStatus = RabbitSyncStatus.synced,
  });

  final int id;
  final String uuid;
  final int userId;
  final String name;
  final String breed;
  final String sex;
  final String birthDate;
  final double? weight;
  final String status;
  final String notes;
  final int version;
  final String createdAt;
  final String updatedAt;
  final String? deletedAt;
  final RabbitSyncStatus syncStatus;

  factory Rabbit.fromJson(Map<String, dynamic> json) {
    return Rabbit(
      id: json['id'] as int,
      uuid: json['uuid'] as String,
      userId: (json['user'] as num?)?.toInt() ?? 0,
      name: json['name'] as String,
      breed: json['breed'] as String,
      sex: json['sex'] as String,
      birthDate: json['birth_date'] as String,
      weight: (json['weight'] as num?)?.toDouble(),
      status: json['status'] as String,
      notes: json['notes'] as String? ?? '',
      version: (json['version'] as num?)?.toInt() ?? 1,
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String,
      deletedAt: json['deleted_at'] as String?,
      syncStatus: RabbitSyncStatus.synced,
    );
  }

  Rabbit copyWith({
    int? id,
    String? uuid,
    int? userId,
    String? name,
    String? breed,
    String? sex,
    String? birthDate,
    double? weight,
    bool clearWeight = false,
    String? status,
    String? notes,
    int? version,
    String? createdAt,
    String? updatedAt,
    String? deletedAt,
    bool clearDeletedAt = false,
    RabbitSyncStatus? syncStatus,
  }) {
    return Rabbit(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      breed: breed ?? this.breed,
      sex: sex ?? this.sex,
      birthDate: birthDate ?? this.birthDate,
      weight: clearWeight ? null : (weight ?? this.weight),
      status: status ?? this.status,
      notes: notes ?? this.notes,
      version: version ?? this.version,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }
}
