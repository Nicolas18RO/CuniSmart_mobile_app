import 'dart:convert';

import '../core/errors/api_exception.dart';
import '../core/network/api_client.dart';
import '../models/sensor_reading.dart';

/// Sensor readings API: GET `/api/sensor-readings/`.
class SensorService {
  SensorService(this._client);

  final ApiClient _client;

  static const String _path = '/api/sensor-readings/';

  Future<List<SensorReading>> fetchSensorReadings() async {
    try {
      final raw = await _client.get(
        _path,
        headers: {'Accept': 'application/json'},
      );
      final decoded = jsonDecode(raw) as dynamic;
      if (decoded is! List) {
        throw ApiException('Expected JSON array from GET $_path');
      }
      return decoded
          .map((e) => SensorReading.fromJson(e as Map<String, dynamic>))
          .toList();
    } on ApiException {
      rethrow;
    } catch (e, st) {
      Error.throwWithStackTrace(
        ApiException('Network or parse error: $e'),
        st,
      );
    }
  }
}
