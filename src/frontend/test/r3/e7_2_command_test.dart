import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/local/sync_command.dart';

void main() {
  for (final stage in ['e7_2', 'e7_3']) {
    test('$stage Dart matches Python canonical bytes and SHA-256', () {
      final vectors = jsonDecode(
        File('../backend/core/fixtures/${stage}_commands.json')
            .readAsStringSync(),
      ) as List;
      for (final vector in vectors) {
        final command = vector['command'] as Map<String, dynamic>;
        final canonical = canonicalSyncCommand(
          entityType: command['entity_type'] as String,
          action: command['action'] as String,
          destination: command['destination'] as String,
          payload: command['payload'] as Map<String, dynamic>,
          expectedVersion: command['expected_version'] as int?,
        );
        expect(canonical, vector['canonical']);
        expect(syncRequestHash(canonical), vector['sha256']);
      }
      expect(
          vectors.map((v) => v['sha256']).toSet(), hasLength(vectors.length));
    });
  }
}
