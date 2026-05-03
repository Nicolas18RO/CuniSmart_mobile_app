import 'package:flutter/foundation.dart';

import '../core/errors/api_exception.dart';
import '../core/state/async_view_state.dart';
import '../core/state/submit_state.dart';
import '../models/rabbit.dart';
import '../services/rabbit_service.dart';

/// MVVM: rabbit list + create flow with standardized async + submit states.
class RabbitViewModel extends ChangeNotifier {
  RabbitViewModel(this._rabbitService);

  final RabbitService _rabbitService;

  AsyncViewState<List<Rabbit>> _listState = const AsyncInitial<List<Rabbit>>();
  SubmitState _submitState = const SubmitIdle();

  /// Last successful list from API (may be empty).
  List<Rabbit> _lastSuccessfulRabbits = [];

  /// True after any successful fetch (load or post-create refresh).
  bool _hasLoadedSuccessfully = false;

  bool _listLoadInFlight = false;

  AsyncViewState<List<Rabbit>> get listState => _listState;
  SubmitState get submitState => _submitState;

  bool get isSubmitting => _submitState is SubmitInProgress;

  /// True while a list request is running (initial or refresh).
  bool get isListLoading => _listState is AsyncLoading<List<Rabbit>>;

  /// Block FAB during first load (no cache yet). Allow create during refresh when we have prior data.
  bool get shouldBlockCreateFab {
    return switch (_listState) {
      AsyncLoading(:final cachedData) => cachedData == null,
      _ => false,
    };
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

  /// `null` = never loaded successfully (show full-screen spinner). Otherwise show list/empty + refresh UI.
  List<Rabbit>? _cacheForLoading() {
    if (!_hasLoadedSuccessfully) return null;
    return List<Rabbit>.unmodifiable(_lastSuccessfulRabbits);
  }

  /// Initial load or refresh. Keeps last successful data (including empty list) on refresh failure.
  Future<void> loadRabbits() async {
    if (_listLoadInFlight) return;
    _listLoadInFlight = true;

    _listState = AsyncLoading<List<Rabbit>>(cachedData: _cacheForLoading());
    notifyListeners();

    try {
      final list = await _rabbitService.fetchRabbits();
      _hasLoadedSuccessfully = true;
      _lastSuccessfulRabbits = List<Rabbit>.unmodifiable(list);
      _listState = AsyncSuccess<List<Rabbit>>(list);
    } catch (e) {
      final message = _formatError(e);
      if (_hasLoadedSuccessfully) {
        _listState = AsyncError<List<Rabbit>>(
          message,
          cachedData: List<Rabbit>.unmodifiable(_lastSuccessfulRabbits),
        );
      } else {
        _listState = AsyncError<List<Rabbit>>(message);
      }
    } finally {
      _listLoadInFlight = false;
      notifyListeners();
    }
  }

  /// Create rabbit, refresh list on success. Prevents overlapping submits.
  Future<bool> createRabbit({
    required String name,
    required String breed,
    required String sex,
    required String birthDate,
    double? weight,
    required String status,
    String notes = '',
  }) async {
    if (_submitState is SubmitInProgress) return false;

    _submitState = const SubmitInProgress();
    notifyListeners();

    try {
      await _rabbitService.createRabbit(
        name: name,
        breed: breed,
        sex: sex,
        birthDate: birthDate,
        weight: weight,
        status: status,
        notes: notes,
      );
      final list = await _rabbitService.fetchRabbits();
      _hasLoadedSuccessfully = true;
      _lastSuccessfulRabbits = List<Rabbit>.unmodifiable(list);
      _listState = AsyncSuccess<List<Rabbit>>(list);
      _submitState = const SubmitIdle();
      notifyListeners();
      return true;
    } catch (e) {
      _submitState = SubmitFailed(_formatError(e));
      notifyListeners();
      return false;
    }
  }

  void clearSubmitError() {
    if (_submitState is SubmitFailed) {
      _submitState = const SubmitIdle();
      notifyListeners();
    }
  }
}
