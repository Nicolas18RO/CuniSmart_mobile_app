import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/errors/api_exception.dart';
import '../core/state/async_view_state.dart';
import '../core/state/submit_state.dart';
import '../models/rabbit.dart';
import '../models/rabbit_qr.dart';
import '../services/rabbit_service.dart';

/// MVVM: rabbit list + create flow with standardized async + submit states.
class RabbitViewModel extends ChangeNotifier {
  RabbitViewModel(this._rabbitService, {Stream<bool>? onlineChanges}) {
    _onlineSub = onlineChanges?.listen((online) {
      if (online) {
        unawaited(loadRabbits());
      } else {
        _rabbitService.disconnected();
      }
    });
  }

  final RabbitService _rabbitService;
  StreamSubscription<bool>? _onlineSub;

  AsyncViewState<List<Rabbit>> _listState = const AsyncInitial<List<Rabbit>>();
  SubmitState _submitState = const SubmitIdle();

  /// Last successful list from API (may be empty).
  List<Rabbit> _lastSuccessfulRabbits = [];

  /// True after any successful fetch (load or post-create refresh).
  bool _hasLoadedSuccessfully = false;

  bool _listLoadInFlight = false;

  int? _stateGeneration;

  void _refreshAccountState() {
    final generation = _rabbitService.generation;
    if (_stateGeneration == generation) return;
    _stateGeneration = generation;
    _listState = const AsyncInitial<List<Rabbit>>();
    _submitState = const SubmitIdle();
    _lastSuccessfulRabbits = [];
    _hasLoadedSuccessfully = false;
    _listLoadInFlight = false;
  }

  AsyncViewState<List<Rabbit>> get listState {
    _refreshAccountState();
    return _listState;
  }

  SubmitState get submitState {
    _refreshAccountState();
    return _submitState;
  }

  bool get isSubmitting => submitState is SubmitInProgress;

  /// True while a list request is running (initial or refresh).
  bool get isListLoading => listState is AsyncLoading<List<Rabbit>>;

  /// Block FAB during first load (no cache yet). Allow create during refresh when we have prior data.
  bool get shouldBlockCreateFab {
    return switch (listState) {
      AsyncLoading(:final cachedData) => cachedData == null,
      _ => false,
    };
  }

  String _formatError(Object error) {
    if (error is ApiException) {
      if (error.code == 'network') {
        return 'No fue posible conectar con el servidor. Intenta nuevamente.';
      }
      if ((error.statusCode ?? 0) >= 500) {
        return 'Ocurrió un problema al consultar la información. Intenta nuevamente.';
      }
      return error.message;
    }
    return 'No se pudo completar la operación. Intenta nuevamente.';
  }

  /// `null` = never loaded successfully (show full-screen spinner). Otherwise show list/empty + refresh UI.
  List<Rabbit>? _cacheForLoading() {
    if (!_hasLoadedSuccessfully) return null;
    return List<Rabbit>.unmodifiable(_lastSuccessfulRabbits);
  }

  /// Initial load or refresh. Keeps last successful data (including empty list) on refresh failure.
  Future<void> loadRabbits() async {
    _refreshAccountState();
    final generation = _stateGeneration;
    if (_listLoadInFlight) return;
    _listLoadInFlight = true;

    try {
      final local = await _rabbitService.readLocalRabbits();
      if (generation != _rabbitService.generation) return;
      if (local.isNotEmpty) {
        _hasLoadedSuccessfully = true;
        _lastSuccessfulRabbits = List<Rabbit>.unmodifiable(local);
      }

      _listState = AsyncLoading<List<Rabbit>>(cachedData: _cacheForLoading());
      notifyListeners();

      await _rabbitService.syncPending();
      if (generation != _rabbitService.generation) return;
      final list = await _rabbitService.fetchRabbits();
      if (generation != _rabbitService.generation) return;
      _hasLoadedSuccessfully = true;
      _lastSuccessfulRabbits = List<Rabbit>.unmodifiable(list);
      _listState = AsyncSuccess<List<Rabbit>>(list);
    } catch (e) {
      if (generation != _rabbitService.generation) return;
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
      if (generation == _rabbitService.generation) {
        _listLoadInFlight = false;
        notifyListeners();
      }
    }
  }

  Future<Rabbit?> loadRabbitDetail(String uuid) async {
    try {
      return await _rabbitService.fetchRabbit(uuid);
    } catch (_) {
      return null;
    }
  }

  /// Resolve a scanned QR to a rabbit (local first, then API if online).
  Future<Rabbit?> lookupFromQr(String raw) async {
    _refreshAccountState();
    final generation = _stateGeneration;
    final uuid = RabbitQr.parseUuid(raw);
    if (uuid == null) {
      _submitState = const SubmitFailed('Este código no es de CuniSmart');
      notifyListeners();
      return null;
    }
    if (_submitState is SubmitInProgress) return null;

    _submitState = const SubmitInProgress();
    notifyListeners();

    try {
      final rabbit = await _rabbitService.lookupByUuid(uuid);
      if (generation != _rabbitService.generation) return null;
      _submitState = const SubmitIdle();
      notifyListeners();
      return rabbit;
    } catch (e) {
      if (generation != _rabbitService.generation) return null;
      _submitState = SubmitFailed(_formatError(e));
      notifyListeners();
      return null;
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
    String genealogyKnowledge = 'UNKNOWN',
  }) async {
    _refreshAccountState();
    final generation = _stateGeneration;
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
        genealogyKnowledge: genealogyKnowledge,
      );
      if (generation != _rabbitService.generation) return false;
      final list = await _rabbitService.readLocalRabbits();
      if (generation != _rabbitService.generation) return false;
      _hasLoadedSuccessfully = true;
      _lastSuccessfulRabbits = List<Rabbit>.unmodifiable(list);
      _listState = AsyncSuccess<List<Rabbit>>(list);
      _submitState = const SubmitIdle();
      notifyListeners();
      return true;
    } catch (e) {
      if (generation != _rabbitService.generation) return false;
      _submitState = SubmitFailed(_formatError(e));
      notifyListeners();
      return false;
    }
  }

  /// Update rabbit, refresh list on success. Prevents overlapping submits.
  Future<bool> updateRabbit({
    required String uuid,
    required String name,
    required String breed,
    required String sex,
    required String birthDate,
    double? weight,
    required String status,
    String notes = '',
    String? genealogyKnowledge,
  }) async {
    _refreshAccountState();
    final generation = _stateGeneration;
    if (_submitState is SubmitInProgress) return false;

    _submitState = const SubmitInProgress();
    notifyListeners();

    try {
      await _rabbitService.updateRabbit(
        uuid: uuid,
        name: name,
        breed: breed,
        sex: sex,
        birthDate: birthDate,
        weight: weight,
        status: status,
        notes: notes,
        genealogyKnowledge: genealogyKnowledge,
      );
      if (generation != _rabbitService.generation) return false;
      final list = await _rabbitService.readLocalRabbits();
      if (generation != _rabbitService.generation) return false;
      _hasLoadedSuccessfully = true;
      _lastSuccessfulRabbits = List<Rabbit>.unmodifiable(list);
      _listState = AsyncSuccess<List<Rabbit>>(list);
      _submitState = const SubmitIdle();
      notifyListeners();
      return true;
    } catch (e) {
      if (generation != _rabbitService.generation) return false;
      _submitState = SubmitFailed(_formatError(e));
      notifyListeners();
      return false;
    }
  }

  /// Keep the remote snapshot and clear CONFLICT.
  Future<Rabbit?> resolveConflictKeepRemote(String uuid) async {
    return _resolveConflict(
      uuid,
      () => _rabbitService.resolveConflictKeepRemote(uuid),
    );
  }

  /// Retry local fields using the remote version.
  Future<Rabbit?> resolveConflictKeepLocal(String uuid) async {
    return _resolveConflict(
      uuid,
      () => _rabbitService.resolveConflictKeepLocal(uuid),
    );
  }

  Future<Rabbit?> _resolveConflict(
    String uuid,
    Future<void> Function() action,
  ) async {
    _refreshAccountState();
    final generation = _stateGeneration;
    if (_submitState is SubmitInProgress) return null;

    _submitState = const SubmitInProgress();
    notifyListeners();

    try {
      await action();
      if (generation != _rabbitService.generation) return null;
      final list = await _rabbitService.readLocalRabbits();
      if (generation != _rabbitService.generation) return null;
      _hasLoadedSuccessfully = true;
      _lastSuccessfulRabbits = List<Rabbit>.unmodifiable(list);
      _listState = AsyncSuccess<List<Rabbit>>(list);
      _submitState = const SubmitIdle();
      notifyListeners();
      for (final rabbit in list) {
        if (rabbit.uuid == uuid) return rabbit;
      }
      return null;
    } catch (e) {
      if (generation != _rabbitService.generation) return null;
      _submitState = SubmitFailed(_formatError(e));
      notifyListeners();
      return null;
    }
  }

  /// Delete rabbit, refresh list on success. Prevents overlapping submits.
  Future<bool> deleteRabbit(String uuid) async {
    _refreshAccountState();
    final generation = _stateGeneration;
    if (_submitState is SubmitInProgress) return false;

    _submitState = const SubmitInProgress();
    notifyListeners();

    try {
      await _rabbitService.deleteRabbit(uuid);
      if (generation != _rabbitService.generation) return false;
      final list = await _rabbitService.readLocalRabbits();
      if (generation != _rabbitService.generation) return false;
      _hasLoadedSuccessfully = true;
      _lastSuccessfulRabbits = List<Rabbit>.unmodifiable(list);
      _listState = AsyncSuccess<List<Rabbit>>(list);
      _submitState = const SubmitIdle();
      notifyListeners();
      return true;
    } catch (e) {
      if (generation != _rabbitService.generation) return false;
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

  @override
  void dispose() {
    _onlineSub?.cancel();
    super.dispose();
  }
}
