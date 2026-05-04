import 'dart:convert';

import '../core/errors/api_exception.dart';
import '../core/network/api_client.dart';
import '../models/rabbit.dart';

/// Rabbit API: GET/POST `/api/rabbits/`, PUT/PATCH/DELETE `/api/rabbits/{id}/`.
class RabbitService {
  RabbitService(this._client);

  final ApiClient _client;

  static const String _path = '/api/rabbits/';

  Future<List<Rabbit>> fetchRabbits() async {
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
          .map((e) => Rabbit.fromJson(e as Map<String, dynamic>))
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

  Future<Rabbit> createRabbit({
    required String name,
    required String breed,
    required String sex,
    required String birthDate,
    double? weight,
    required String status,
    String notes = '',
  }) async {
    try {
      final body = jsonEncode(<String, dynamic>{
        'name': name,
        'breed': breed,
        'sex': sex,
        'birth_date': birthDate,
        'status': status,
        'notes': notes,
        if (weight != null) 'weight': weight,
      });
      final raw = await _client.post(
        _path,
        body: body,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      );
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return Rabbit.fromJson(decoded);
    } on ApiException {
      rethrow;
    } catch (e, st) {
      Error.throwWithStackTrace(
        ApiException('Network or parse error: $e'),
        st,
      );
    }
  }

  Future<Rabbit> updateRabbit({
    required int id,
    required String name,
    required String breed,
    required String sex,
    required String birthDate,
    double? weight,
    required String status,
    String notes = '',
  }) async {
    try {
      final body = jsonEncode(<String, dynamic>{
        'name': name,
        'breed': breed,
        'sex': sex,
        'birth_date': birthDate,
        'status': status,
        'notes': notes,
        if (weight != null) 'weight': weight,
      });
      final path = '$_path$id/';
      final raw = await _client.put(
        path,
        body: body,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      );
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return Rabbit.fromJson(decoded);
    } on ApiException {
      rethrow;
    } catch (e, st) {
      Error.throwWithStackTrace(
        ApiException('Network or parse error: $e'),
        st,
      );
    }
  }

  Future<void> deleteRabbit(int id) async {
    try {
      final path = '$_path$id/';
      await _client.delete(
        path,
        headers: {'Accept': 'application/json'},
      );
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
