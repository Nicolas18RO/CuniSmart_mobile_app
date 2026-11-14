import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

const _methods = {
  'PARENT_LINK': {'CREATE': 'PUT', 'UPDATE': 'PUT', 'DELETE': 'DELETE'},
  'REPRODUCTIVE_EVENT': {
    'CREATE': 'POST',
    'UPDATE': 'PATCH',
    'DELETE': 'DELETE'
  },
};

int _compareCodePoints(String a, String b) {
  final left = a.runes.iterator;
  final right = b.runes.iterator;
  while (left.moveNext()) {
    if (!right.moveNext()) return 1;
    final comparison = left.current.compareTo(right.current);
    if (comparison != 0) return comparison;
  }
  return right.moveNext() ? -1 : 0;
}

Object? _sortJson(Object? value) {
  if (value == null || value is bool || value is String) return value;
  if (value is int && value >= -9007199254740991 && value <= 9007199254740991) {
    return value;
  }
  if (value is List) return value.map(_sortJson).toList();
  if (value is Map<String, Object?>) {
    return SplayTreeMap<String, Object?>.from(
      value.map((key, value) => MapEntry(key, _sortJson(value))),
      _compareCodePoints,
    );
  }
  throw ArgumentError('Command accepts only JSON with safe integers');
}

String canonicalSyncCommand({
  required String entityType,
  required String action,
  required String destination,
  required Map<String, Object?> payload,
  int? expectedVersion,
  int contractVersion = 1,
}) {
  final method = _methods[entityType]?[action];
  if (method == null ||
      contractVersion != 1 ||
      !RegExp(r'^/[^\s?#]*$').hasMatch(destination) ||
      destination.codeUnits.any((unit) => unit < 33 || unit > 126) ||
      (expectedVersion != null &&
          (expectedVersion < 1 || expectedVersion > 2147483647))) {
    throw ArgumentError('Invalid sync command');
  }
  return jsonEncode(_sortJson({
    'action': action,
    'destination': destination,
    'entityType': entityType,
    'expectedVersion': expectedVersion,
    'method': method,
    'payload': payload,
    'version': contractVersion,
  }));
}

String syncRequestHash(String canonicalCommand) =>
    sha256.convert(utf8.encode(canonicalCommand)).toString();
