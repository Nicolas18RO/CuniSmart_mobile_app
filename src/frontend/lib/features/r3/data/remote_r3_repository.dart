import 'dart:convert';

import '../../../core/errors/api_exception.dart';
import '../../../core/network/api_client.dart';
import '../domain/r3_models.dart';
import '../domain/r3_repository.dart';

class RemoteR3Repository implements R3Repository {
  RemoteR3Repository(this._client);
  final ApiClient _client;
  static const _events = '/api/reproductive-events/';

  Map<String, dynamic> _object(String raw) {
    final value = jsonDecode(raw);
    if (value is! Map) {
      throw ApiException('La respuesta del servidor no es válida.');
    }
    return Map<String, dynamic>.from(value);
  }

  @override
  Future<Pedigree> pedigree(String rabbitUuid) async => Pedigree.fromJson(
        _object(await _client.get('/api/rabbits/$rabbitUuid/pedigree/')),
      );

  @override
  Future<void> setParent(
      {required String childUuid,
      required String role,
      required String parentUuid,
      int? version}) async {
    await _client.put(
      '/api/rabbits/$childUuid/parents/$role/',
      body: jsonEncode(
          {'parent_uuid': parentUuid, if (version != null) 'version': version}),
    );
  }

  @override
  Future<void> clearParent(
      {required String childUuid,
      required String role,
      required int version}) async {
    await _client.delete(
      '/api/rabbits/$childUuid/parents/$role/',
      body: jsonEncode({'version': version}),
    );
  }

  @override
  Future<KinshipEvaluation> kinship(
      {required String firstUuid,
      required String secondUuid,
      String mode = 'relationship'}) async {
    final query =
        Uri(queryParameters: {'a': firstUuid, 'b': secondUuid, 'mode': mode})
            .query;
    return KinshipEvaluation.fromJson(
      _object(await _client.get('/api/rabbits/kinship/?$query')),
    );
  }

  @override
  Future<List<ReproductiveEvent>> events() async {
    final value = jsonDecode(await _client.get(_events));
    if (value is! List) throw ApiException('La lista de eventos no es válida.');
    return value
        .map((item) =>
            ReproductiveEvent.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  @override
  Future<ReproductiveEvent> event(String uuid) async =>
      ReproductiveEvent.fromJson(
        _object(await _client.get('$_events$uuid/')),
      );

  @override
  Future<ReproductiveEvent> createEvent(
          {required String maleUuid,
          required String femaleUuid,
          required String matingDate,
          String notes = ''}) async =>
      ReproductiveEvent.fromJson(
        _object(await _client.post(_events,
            body: jsonEncode({
              'male_uuid': maleUuid,
              'female_uuid': femaleUuid,
              'mating_date': matingDate,
              'notes': notes,
            }))),
      );

  @override
  Future<ReproductiveEvent> updateEvent(
          {required String uuid,
          required int version,
          String? matingDate,
          String? notes}) async =>
      ReproductiveEvent.fromJson(
        _object(await _client.patch('$_events$uuid/',
            body: jsonEncode({
              'version': version,
              if (matingDate != null) 'mating_date': matingDate,
              if (notes != null) 'notes': notes,
            }))),
      );

  @override
  Future<void> deleteEvent({required String uuid, required int version}) async {
    await _client.delete('$_events$uuid/',
        body: jsonEncode({'version': version}));
  }

  @override
  Future<List<ReproductiveEvent>> calendar(
      {required String startDate, required String endDate}) async {
    final query =
        Uri(queryParameters: {'start_date': startDate, 'end_date': endDate})
            .query;
    final object = _object(await _client.get('${_events}calendar/?$query'));
    final rows = object['events'];
    if (rows is! List) throw ApiException('El calendario no es válido.');
    return rows
        .map((item) =>
            ReproductiveEvent.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }
}
