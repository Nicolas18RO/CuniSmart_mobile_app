import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/errors/api_exception.dart';
import '../core/state/async_view_state.dart';
import '../models/sensor_reading.dart';
import '../services/sensor_service.dart';

/// IoT dashboard: readings list + derived slices + periodic refresh.
class SensorViewModel extends ChangeNotifier {
  SensorViewModel(this._sensorService);

  final SensorService _sensorService;

  static const Duration _pollInterval = Duration(seconds: 4);

  AsyncViewState<List<SensorReading>> _readingsState =
      const AsyncInitial<List<SensorReading>>();

  List<SensorReading> _lastSuccessfulReadings = [];
  bool _hasLoadedSuccessfully = false;
  bool _loadInFlight = false;
  Timer? _pollTimer;

  AsyncViewState<List<SensorReading>> get readingsState => _readingsState;

  bool get isLoading => _readingsState is AsyncLoading<List<SensorReading>>;

  /// Latest list used for derived metrics (success, refresh cache, or error cache).
  List<SensorReading>? get _currentList {
    return switch (_readingsState) {
      AsyncSuccess<List<SensorReading>>(:final data) => data,
      AsyncLoading<List<SensorReading>>(:final cachedData) => cachedData,
      AsyncError<List<SensorReading>>(:final cachedData) => cachedData,
      _ => null,
    };
  }

  /// Most recent room temperature sample (device-only row: temp only).
  double? get latestRoomTemperature {
    final list = _currentList;
    if (list == null) return null;
    final rows = list
        .where(
          (r) =>
              r.temperature != null && r.weight == null && r.waterLevel == null,
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return rows.isEmpty ? null : rows.first.temperature;
  }

  /// Most recent tank level sample (water only).
  double? get latestTankWaterLevel {
    final list = _currentList;
    if (list == null) return null;
    final rows = list
        .where(
          (r) =>
              r.waterLevel != null && r.weight == null && r.temperature == null,
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return rows.isEmpty ? null : rows.first.waterLevel;
  }

  /// Weight-scale events (newest first).
  List<SensorReading> get weightEvents {
    final list = _currentList;
    if (list == null) return [];
    final rows = list.where((r) => r.weight != null).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return rows;
  }

  List<SensorReading>? _cacheForLoading() {
    if (!_hasLoadedSuccessfully) return null;
    return List<SensorReading>.unmodifiable(_lastSuccessfulReadings);
  }

  String _formatError(Object error) {
    if (error is ApiException) {
      final code = error.statusCode;
      if (code != null) {
        return 'Request failed ($code): ${error.message}';
      }
      return error.message;
    }
    return error.toString();
  }

  Future<void> loadSensorReadings() async {
    if (_loadInFlight) return;
    _loadInFlight = true;

    _readingsState =
        AsyncLoading<List<SensorReading>>(cachedData: _cacheForLoading());
    notifyListeners();

    try {
      final list = await _sensorService.fetchSensorReadings();
      _hasLoadedSuccessfully = true;
      _lastSuccessfulReadings = List<SensorReading>.unmodifiable(list);
      _readingsState = AsyncSuccess<List<SensorReading>>(list);
    } catch (e) {
      final message = _formatError(e);
      if (_hasLoadedSuccessfully) {
        _readingsState = AsyncError<List<SensorReading>>(
          message,
          cachedData: List<SensorReading>.unmodifiable(_lastSuccessfulReadings),
        );
      } else {
        _readingsState = AsyncError<List<SensorReading>>(message);
      }
    } finally {
      _loadInFlight = false;
      notifyListeners();
    }
  }

  /// Starts [loadSensorReadings] on an interval. Safe to call multiple times.
  void startPolling() {
    if (_pollTimer != null) return;
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      unawaited(loadSensorReadings());
    });
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}
