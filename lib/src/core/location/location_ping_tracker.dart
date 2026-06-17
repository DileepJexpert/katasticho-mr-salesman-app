import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';
import '../storage/offline_queue.dart';
import '../storage/offline_queue_provider.dart';
import '../storage/session_store.dart';
import 'background_location_service.dart';
import 'location_service.dart';

/// Single shared tracker so starting from any screen reuses one service.
final locationPingTrackerProvider = Provider<LocationPingTracker>((ref) {
  final tracker = LocationPingTracker(
    api: ref.watch(apiClientProvider),
    queue: ref.watch(offlineQueueProvider),
    location: LocationService(),
    sessionStore: SessionStore(),
  );
  ref.onDispose(tracker.stop);
  return tracker;
});

/// Sends a GPS breadcrumb ping every [interval] while a route execution
/// is in progress, so the back office can see the salesperson live.
///
/// Pings that fail with a network error are queued in the offline queue
/// and replayed by the existing sync loop.
///
/// Implementation: when [BackgroundLocationService] has been initialized
/// (call [BackgroundLocationService.initialize] from main.dart), `start`
/// delegates to a foreground service that survives backgrounding. As a
/// safety net the in-app Timer also runs when the tracker is alive, so:
///  - foreground app → both fire, dedupe is fine because pings are
///    append-only at the server (same coordinates at slightly different
///    timestamps make a denser trail, not corrupt state);
///  - backgrounded app → the foreground service keeps pinging on Android;
///  - foreground service unavailable (init failed, plugin not bundled,
///    permission denied) → the in-app Timer is the fallback.
class LocationPingTracker {
  LocationPingTracker({
    required this.api,
    required this.queue,
    required this.location,
    required this.sessionStore,
    this.interval = const Duration(minutes: 3),
  });

  final FieldApiClient api;
  final OfflineQueue queue;
  final LocationService location;
  final SessionStore sessionStore;
  final Duration interval;

  Timer? _timer;
  String? _executionId;

  bool get isTracking => _timer != null;
  String? get executionId => _executionId;

  /// Starts (or re-targets) tracking for the given route execution.
  Future<void> start(String executionId) async {
    if (_timer != null && _executionId == executionId) return;
    await stop();
    _executionId = executionId;

    // Drive the background service so pings keep flowing while the app
    // is backgrounded. Failures are silent — the in-app Timer below acts
    // as the fallback for foreground use.
    try {
      final token = api.session?.accessToken ?? '';
      await BackgroundLocationService.start(
        executionId: executionId,
        authToken: token,
      );
    } catch (_) {
      // Plugin missing on web / fallback platforms — Timer still runs.
    }

    _timer = Timer.periodic(interval, (_) => _ping());
    _ping();
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _executionId = null;
    try {
      await BackgroundLocationService.stop();
    } catch (_) {
      // ignored — best-effort
    }
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
