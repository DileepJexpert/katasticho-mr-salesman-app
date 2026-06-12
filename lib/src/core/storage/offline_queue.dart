import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../network/api_client.dart';

/// A single pending offline action waiting to be replayed against the backend.
class OfflineAction {
  OfflineAction({
    required this.id,
    required this.type,
    required this.endpoint,
    required this.method,
    required this.body,
    required this.createdAt,
    this.retryCount = 0,
  });

  /// Unique id (uuid v4).
  final String id;

  /// One of: CHECK_IN, CHECK_OUT, RECORD_ORDER, RECORD_COLLECTION, EXPENSE.
  final String type;

  /// Full API path, e.g. /api/v1/field-sales/visits/{id}/check-in
  final String endpoint;

  /// HTTP method (currently only POST is replayed).
  final String method;

  /// JSON body to replay.
  final Map<String, dynamic> body;

  /// ISO-8601 timestamp of when the action was queued.
  final String createdAt;

  /// Number of failed replay attempts so far.
  int retryCount;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'endpoint': endpoint,
    'method': method,
    'body': body,
    'createdAt': createdAt,
    'retryCount': retryCount,
  };

  factory OfflineAction.fromJson(Map<String, dynamic> json) => OfflineAction(
    id: json['id']?.toString() ?? '',
    type: json['type']?.toString() ?? 'UNKNOWN',
    endpoint: json['endpoint']?.toString() ?? '',
    method: json['method']?.toString() ?? 'POST',
    body: (json['body'] is Map)
        ? Map<String, dynamic>.from(json['body'] as Map)
        : <String, dynamic>{},
    createdAt: json['createdAt']?.toString() ?? '',
    retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
  );
}

/// Result summary for a [OfflineQueue.processQueue] run.
class QueueProcessResult {
  const QueueProcessResult({
    required this.synced,
    required this.failed,
    required this.dropped,
  });

  final int synced;
  final int failed;
  final int dropped;
}

/// SharedPreferences-backed queue of actions captured while offline.
///
/// Each action is replayed via [FieldApiClient.rawPost]; on success it is
/// removed, on failure its retryCount is incremented, and after
/// [maxRetries] failures it is dropped permanently.
class OfflineQueue {
  static const _storageKey = 'field.offline.queue';
  static const maxRetries = 5;

  static const _uuid = Uuid();

  Future<List<OfflineAction>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => OfflineAction.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<OfflineAction> actions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(actions.map((a) => a.toJson()).toList()),
    );
  }

  /// Adds a new pending action and returns it.
  Future<OfflineAction> enqueue({
    required String type,
    required String endpoint,
    String method = 'POST',
    required Map<String, dynamic> body,
  }) async {
    final action = OfflineAction(
      id: _uuid.v4(),
      type: type,
      endpoint: endpoint,
      method: method,
      body: body,
      createdAt: DateTime.now().toIso8601String(),
    );
    final actions = await _load();
    actions.add(action);
    await _save(actions);
    return action;
  }

  /// All pending actions, oldest first.
  Future<List<OfflineAction>> get items => _load();

  /// Number of pending actions.
  Future<int> get pendingCount async => (await _load()).length;

  /// Removes a single action by id.
  Future<void> remove(String id) async {
    final actions = await _load();
    actions.removeWhere((a) => a.id == id);
    await _save(actions);
  }

  /// Drops every pending action.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  /// Replays every pending action via [FieldApiClient.rawPost].
  ///
  /// Successful actions are removed. Failed actions get retryCount
  /// incremented and are dropped permanently after [maxRetries] attempts.
  Future<QueueProcessResult> processQueue(FieldApiClient api) async {
    final actions = await _load();
    if (actions.isEmpty) {
      return const QueueProcessResult(synced: 0, failed: 0, dropped: 0);
    }

    var synced = 0;
    var failed = 0;
    var dropped = 0;
    final remaining = <OfflineAction>[];

    for (final action in actions) {
      try {
        await api.rawPost(action.endpoint, action.body);
        synced++;
      } catch (_) {
        action.retryCount++;
        if (action.retryCount >= maxRetries) {
          dropped++;
        } else {
          failed++;
          remaining.add(action);
        }
      }
    }

    await _save(remaining);
    return QueueProcessResult(synced: synced, failed: failed, dropped: dropped);
  }
}
