import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_controller.dart';
import '../network/api_client.dart';
import '../storage/offline_queue.dart';
import '../storage/offline_queue_provider.dart';
import 'location_service.dart';

/// Single shared tracker so starting from any screen reuses one timer.
final locationPingTrackerProvider = Provider<LocationPingTracker>((ref) {
  final tracker = LocationPingTracker(
    api: ref.watch(apiClientProvider),
    queue: ref.watch(offlineQueueProvider),
    location: LocationService(),
  );
  ref.onDispose(tracker.stop);
  return tracker;
});

/// Sends a GPS breadcrumb ping every [interval] while a route execution
/// is in progress, so the back office can see the salesperson live.
///
/// Pings that fail with a network error are queued in the offline queue
/// and replayed by the existing sync loop. Foreground-only by design —
/// tracking stops when the route is completed or the app is closed.
class LocationPingTracker {
  LocationPingTracker({
    required this.api,
    required this.queue,
    required this.location,
    this.interval = const Duration(minutes: 3),
  });

  final FieldApiClient api;
  final OfflineQueue queue;
  final LocationService location;
  final Duration interval;

  Timer? _timer;
  String? _executionId;

  bool get isTracking => _timer != null;
  String? get executionId => _executionId;

  /// Starts (or re-targets) tracking for the given route execution.
  void start(String executionId) {
    if (_timer != null && _executionId == executionId) return;
    stop();
    _executionId = executionId;
    _timer = Timer.periodic(interval, (_) => _ping());
    _ping();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _executionId = null;
  }

  Future<void> _ping() async {
    final executionId = _executionId;
    if (executionId == null) return;

    FieldLocation? loc;
    try {
      loc = await location.currentLocation();
    } catch (_) {
      loc = null;
    }
    if (loc == null) return;

    final ping = <String, dynamic>{
      'latitude': loc.latitude,
      'longitude': loc.longitude,
      'accuracyM': loc.accuracyMeters,
      'recordedAt': DateTime.now().toUtc().toIso8601String(),
      'routeExecutionId': executionId,
    };

    try {
      await api.sendLocationPings([ping]);
    } catch (_) {
      // Queue with the original recordedAt so the trail stays accurate
      // even when the ping is replayed later.
      await queue.enqueue(
        type: 'LOCATION_PING',
        endpoint: '/api/v1/field-sales/locations/ping',
        body: {
          'pings': [ping],
        },
      );
    }
  }
}
