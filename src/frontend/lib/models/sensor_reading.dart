/// Matches DRF `SensorReading` JSON (`sensor_device` and `rabbit` are PKs or null).
class SensorReading {
  const SensorReading({
    required this.id,
    required this.sensorDeviceId,
    this.rabbitId,
    this.temperature,
    this.weight,
    this.waterLevel,
    required this.createdAt,
  });

  final int id;
  final int sensorDeviceId;
  final int? rabbitId;
  final double? temperature;
  final double? weight;
  final double? waterLevel;
  final String createdAt;

  factory SensorReading.fromJson(Map<String, dynamic> json) {
    return SensorReading(
      id: (json['id'] as num).toInt(),
      sensorDeviceId: (json['sensor_device'] as num).toInt(),
      rabbitId: (json['rabbit'] as num?)?.toInt(),
      temperature: (json['temperature'] as num?)?.toDouble(),
      weight: (json['weight'] as num?)?.toDouble(),
      waterLevel: (json['water_level'] as num?)?.toDouble(),
      createdAt: json['created_at'] as String,
    );
  }
}
