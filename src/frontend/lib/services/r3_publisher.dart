import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../core/errors/api_exception.dart';
import '../core/network/api_client.dart';
import '../data/local/r3_acquisition.dart';
import '../data/local/sync_evidence_store.dart';
import 'sync_engine.dart';

class R3Publisher {
  R3Publisher(this.client, this.store);

  final ApiClient client;
  final SyncEvidenceStore store;
  final _random = Random();

  Future<void> drain(
    Future<bool> Function() allowed,
    void Function(Duration) schedule,
    Future<bool> Function()? revalidate,
  ) async {
    final visited = <String>{};
    final acquisition = R3Acquisition(store);
    while (await allowed() && store.isCurrent()) {
      final attempt = await acquisition.next(visited);
      if (attempt == null) {
        final retry = await store.nextPublicationRetry();
        if (retry != null) schedule(retry);
        return;
      }
      if (!await allowed() || !store.isCurrent()) {
        if (store.isCurrent()) {
          await store.recordPublicationFailure(attempt, 'session_paused',
              retryAt: DateTime.now());
        }
        return;
      }
      final command = jsonDecode(attempt.command) as Map<String, dynamic>;
      try {
        final response = await client.sendSyncCommand(
          command['method'] as String,
          command['destination'] as String,
          jsonEncode({
            ...(command['payload'] as Map<String, dynamic>),
            if (command['expectedVersion'] != null)
              'version': command['expectedVersion'],
          }),
          {
            'Content-Type': 'application/json; charset=utf-8',
            'Idempotency-Key': attempt.operationUuid,
            'X-CuniSmart-Sync-Version': '${command['version']}',
            'X-CuniSmart-Sync-Action': command['action'] as String,
          },
        );
        if (!store.isCurrent()) return;
        final status = response.statusCode;
        if (status >= 200 && status < 300) {
          final receipt = _receipt(
              _header(response.headers, 'x-cunismart-sync-receipt'),
              status,
              response.body);
          if (receipt != null && await store.applyReceipt(attempt, receipt)) {
            continue;
          }
          await _retry(attempt, 'r3_invalid_receipt', schedule);
        } else if (status == 429 || status >= 500) {
          await _retry(attempt, 'r3_http_$status', schedule,
              retryAfter: _header(response.headers, 'retry-after'));
        } else if (status == 401) {
          final resumed = revalidate != null && await revalidate();
          if (!store.isCurrent()) return;
          await _retry(attempt, 'r3_auth_paused', resumed ? schedule : (_) {});
          return;
        } else {
          final body = _object(response.body);
          final conflict = status == 409 && body?['code'] == 'version_conflict';
          final snapshot = conflict
              ? snapshotJsonFrom409(ApiException(
                  'Version conflict',
                  statusCode: 409,
                  rawBody: response.body,
                ))
              : null;
          await store.recordPublicationFailure(
              attempt,
              status == 409
                  ? 'r3_${body?['code'] ?? 'conflict'}'
                  : 'r3_http_$status',
              conflict: conflict,
              snapshot: _matchingSnapshot(command, snapshot));
        }
      } on ApiException catch (error) {
        if (!store.isCurrent()) return;
        if (error.code != 'network') rethrow;
        await _retry(attempt, 'r3_network_uncertain', schedule);
      } catch (_) {
        if (!store.isCurrent()) return;
        // Includes a failed local result transaction after remote commit.
        await _retry(attempt, 'r3_confirmation_uncertain', schedule);
      }
    }
  }

  String? _matchingSnapshot(Map<String, dynamic> command, String? raw) {
    if (raw == null) return null;
    final current = _object(raw);
    if (current == null) return null;
    final path = command['destination'];
    final expected = command['entityType'] == 'PARENT_LINK'
        ? "/api/rabbits/${current['child_uuid']}/parents/${current['role']}/"
        : "/api/reproductive-events/${current['uuid']}/";
    return path == expected ? raw : null;
  }

  Map<String, dynamic>? _receipt(String? header, int status, String body) {
    if (header == null || header.length > 4096) return null;
    try {
      final metadata = _object(utf8.decode(base64Url.decode(header)));
      if (metadata == null ||
          metadata['statusCode'] != status ||
          metadata['bodyPresent'] != body.isNotEmpty) return null;
      return {
        ...metadata,
        'responseBody': body.isEmpty ? null : jsonDecode(body)
      };
    } on FormatException {
      return null;
    }
  }

  Map<String, dynamic>? _object(String body) {
    try {
      final value = jsonDecode(body);
      return value is Map<String, dynamic> ? value : null;
    } on FormatException {
      return null;
    }
  }

  String? _header(Map<String, String> headers, String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name) return entry.value;
    }
    return null;
  }

  Future<void> _retry(
      FrozenAttempt attempt, String reason, void Function(Duration) schedule,
      {String? retryAfter}) async {
    final count = (await store.operation(attempt.operationUuid))!.attempts;
    if (count >= 5) {
      await store.recordPublicationFailure(attempt, 'r3_retry_limit:$reason');
      return;
    }
    final now = DateTime.now();
    final backoff =
        Duration(milliseconds: 1000 * (1 << count) + _random.nextInt(1000));
    var target = now.add(backoff);
    if (retryAfter != null) {
      final seconds = int.tryParse(retryAfter);
      try {
        final requested = seconds == null
            ? HttpDate.parse(retryAfter)
            : now.add(Duration(seconds: seconds));
        if (requested.isAfter(target)) target = requested;
      } on FormatException {
        // Invalid Retry-After leaves the calculated backoff.
      }
    }
    await store.recordPublicationFailure(attempt, reason, retryAt: target);
    schedule(target.difference(now));
  }
}
