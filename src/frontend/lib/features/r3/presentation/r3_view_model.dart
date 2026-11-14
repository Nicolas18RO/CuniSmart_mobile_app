import 'package:flutter/foundation.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/state/async_view_state.dart';
import '../../../core/state/submit_state.dart';
import '../application/r3_use_cases.dart';
import '../domain/r3_models.dart';
import '../domain/r3_local_results.dart';

class R3ViewModel extends ChangeNotifier {
  R3ViewModel(this._useCases,
      {this.sessionGeneration, this.sessionUnlocked, this.remoteVerified});
  final R3UseCases _useCases;
  final int Function()? sessionGeneration;
  final bool Function()? sessionUnlocked;
  final bool Function()? remoteVerified;
  bool _disposed = false;

  AsyncViewState<Pedigree> _pedigree = const AsyncInitial();
  AsyncViewState<KinshipEvaluation> _kinship = const AsyncInitial();
  AsyncViewState<List<ReproductiveEvent>> _events = const AsyncInitial();
  AsyncViewState<List<ReproductiveEvent>> _calendar = const AsyncInitial();
  SubmitState _submit = const SubmitIdle();
  int? _generation;
  final _requests = <String, Object>{};
  String? participant;
  ReproductiveRole? participantRole;
  String? fromDate;
  String? toDate;
  bool includeDeletedEvents = false;

  int? get currentGeneration => sessionGeneration?.call();

  bool accepts(int? generation) =>
      !_disposed &&
      generation == currentGeneration &&
      sessionUnlocked?.call() != false;

  void invalidateSession() {
    _generation = currentGeneration;
    _requests.clear();
    _pedigree = const AsyncInitial();
    _kinship = const AsyncInitial();
    _events = const AsyncInitial();
    _calendar = const AsyncInitial();
    _submit = const SubmitIdle();
    participant = null;
    participantRole = null;
    fromDate = null;
    toDate = null;
    includeDeletedEvents = false;
  }

  void _prepare() {
    if (_generation != currentGeneration) invalidateSession();
  }

  AsyncViewState<T> _visible<T>(AsyncViewState<T> state) =>
      _generation == currentGeneration && accepts(_generation)
          ? state
          : const AsyncInitial();

  AsyncViewState<Pedigree> get pedigreeState => _visible(_pedigree);
  AsyncViewState<KinshipEvaluation> get kinshipState => _visible(_kinship);
  AsyncViewState<List<ReproductiveEvent>> get eventsState => _visible(_events);
  AsyncViewState<List<ReproductiveEvent>> get calendarState =>
      _visible(_calendar);
  SubmitState get submitState =>
      _generation == currentGeneration && accepts(_generation)
          ? _submit
          : const SubmitIdle();
  bool get localData => sessionGeneration != null;
  String get sourceLabel => remoteVerified?.call() == false
      ? 'Sin sesión remota verificada. Consultando la copia local.'
      : 'Consultando la copia local.';
  bool get submitting => submitState is SubmitInProgress;

  String _message(Object error) {
    if (error is ApiException) {
      if (error.statusCode == 409 ||
          error.code == 'version_conflict' ||
          error.code == 'versionConflict') {
        return error.statusCode == 409
            ? 'El registro cambió en otro dispositivo. Actualiza y vuelve a intentarlo.'
            : 'El registro local cambió. Actualiza y vuelve a intentarlo.';
      }
      return error.message;
    }
    return 'No se pudo completar la operación R3. Intenta nuevamente.';
  }

  Future<void> _load<T>(String key, Future<T> Function() fetch,
      void Function(AsyncViewState<T>) update) async {
    _prepare();
    final generation = _generation;
    if (!accepts(generation)) return;
    final request = Object();
    _requests[key] = request;
    update(const AsyncLoading());
    notifyListeners();
    AsyncViewState<T> result;
    try {
      result = AsyncSuccess(await fetch());
    } catch (error) {
      result = AsyncError(_message(error));
    }
    if (!accepts(generation) || _requests[key] != request) return;
    update(result);
    notifyListeners();
  }

  Future<bool> _mutate(
      Future<void> Function() action, Future<void> Function() reload,
      {int? expectedGeneration}) async {
    _prepare();
    final generation = _generation;
    if (!accepts(generation) ||
        submitting ||
        (expectedGeneration != null && generation != expectedGeneration)) {
      return false;
    }
    final request = Object();
    _requests['submit'] = request;
    _submit = const SubmitInProgress();
    notifyListeners();
    bool current() => accepts(generation) && _requests['submit'] == request;
    try {
      await action();
      if (!current()) return false;
      await reload();
      if (!current()) return false;
      _submit = const SubmitIdle();
      notifyListeners();
      return true;
    } catch (error) {
      if (current()) {
        _submit = SubmitFailed(_message(error));
        notifyListeners();
      }
      return false;
    }
  }

  Future<void> loadPedigree(String uuid) => _load('pedigree',
      () => _useCases.loadPedigree(uuid), (value) => _pedigree = value);

  Future<bool> setParent(
          {required String child,
          required String role,
          required String parent,
          int? version,
          int? expectedGeneration}) =>
      _mutate(
          () => _useCases.assignParent(
              child: child, role: role, parent: parent, version: version),
          () => loadPedigree(child),
          expectedGeneration: expectedGeneration);

  Future<bool> clearParent(
          {required String child,
          required String role,
          required int version,
          int? expectedGeneration}) =>
      _mutate(
          () => _useCases.removeParent(
              child: child, role: role, version: version),
          () => loadPedigree(child),
          expectedGeneration: expectedGeneration);

  Future<void> evaluate(String first, String second,
          {String mode = 'relationship'}) =>
      _load('kinship', () => _useCases.evaluate(first, second, mode: mode),
          (value) => _kinship = value);

  Future<void> loadEvents() => _load(
      'events',
      () => _useCases.loadEvents(
          participant: participant,
          role: participantRole,
          from: fromDate,
          to: toDate,
          includeDeleted: includeDeletedEvents),
      (value) => _events = value);

  Future<void> filterEvents(
      {String? participant,
      ReproductiveRole? role,
      String? from,
      String? to,
      bool includeDeleted = false}) {
    _prepare();
    this.participant = participant;
    participantRole = role;
    fromDate = from;
    toDate = to;
    includeDeletedEvents = includeDeleted;
    return loadEvents();
  }

  Future<bool> saveEvent(
          {ReproductiveEvent? event,
          required String male,
          required String female,
          required String date,
          required String notes,
          int? expectedGeneration}) =>
      _mutate(() async {
        if (event == null) {
          await _useCases.createEvent(
              male: male, female: female, date: date, notes: notes);
        } else {
          await _useCases.updateEvent(event: event, date: date, notes: notes);
        }
      }, loadEvents, expectedGeneration: expectedGeneration);

  Future<bool> deleteEvent(ReproductiveEvent event,
          {int? expectedGeneration}) =>
      _mutate(() => _useCases.deleteEvent(event), loadEvents,
          expectedGeneration: expectedGeneration);

  Future<void> loadCalendar(String start, String end) => _load('calendar',
      () => _useCases.loadCalendar(start, end), (value) => _calendar = value);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
