/// Matches Django `core.Rabbit` + DRF JSON shape.
class Rabbit {
  const Rabbit({
    required this.id,
    required this.name,
    required this.breed,
    required this.sex,
    required this.birthDate,
    this.weight,
    required this.status,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final String breed;
  final String sex;
  final String birthDate;
  final double? weight;
  final String status;
  final String notes;
  final String createdAt;
  final String updatedAt;

  factory Rabbit.fromJson(Map<String, dynamic> json) {
    return Rabbit(
      id: json['id'] as int,
      name: json['name'] as String,
      breed: json['breed'] as String,
      sex: json['sex'] as String,
      birthDate: json['birth_date'] as String,
      weight: (json['weight'] as num?)?.toDouble(),
      status: json['status'] as String,
      notes: json['notes'] as String? ?? '',
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String,
    );
  }

}
