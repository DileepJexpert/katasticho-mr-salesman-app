import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';

/// Shared-preferences keys the main isolate writes BEFORE starting the
/// background service so the background isolate can read them.
class _Keys {
  static const executionId = 'field.bg.executionId';
  static const sessionToken =
      'field.session..accessToken'; // matches SessionStore
  static const baseUrl = 'field.bg.baseUrl';
}

/// Configures the [FlutterBackgroundService] used to send location pings
/// while the app is backgrounded during a route execution.
///
/// On Android the service runs as a foreground service of type "location"
/// (declared in AndroidManifest.xml). A persistent notification stays
/// visible while tracking is active — required by the OS on 8.0+ and a
/// transparency win for the salesperson.
///
/// On iOS the service runs as a background isolate. iOS may suspend the
/// isolate aggressively under battery pressure, so iOS is effectively
/// "best-effort" and falls back to the in-app foreground timer when the
/// app is in the foreground.
class BackgroundLocationService {
  BackgroundLocationService._();

  /// Identifier passed to the FlutterBackgroundService channel.
  static const _channelId = 'katasticho_field_location_channel';

  /// Min interval between pings, mirrors the in-app tracker.
  static const Duration pingInterval = Duration(minutes: 3);

  static bool _initialized = false;

  /// Call once at app boot (before `runApp`). Idempotent.
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: _channelId,
        initialNotificationTitle: 'Field tracking',
        initialNotificationContent: 'Sending location pings for your route',
        foregroundServiceNotificationId: 8612,
        foregroundServiceTypes: const [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );
  }

  /// Start tracking for the given route execution. Persists the executionId
  /// + auth token + baseUrl so the background isolate can use them, then
  /// kicks the service.
  static Future<void> start({
    required String executionId,
    required String authToken,
    String? baseUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_Keys.executionId, executionId);
    if (authToken.isNotEmpty) {
      // Mirror SessionStore's key so a token refresh in the main isolate
      // is automatically visible to the background isolate.
      await prefs.setString(_Keys.sessionToken, authToken);
    }
    await prefs.setString(_Keys.baseUrl, baseUrl ?? AppConfig.defaultBaseUrl);

    final service = FlutterBackgroundService();
    final running = await service.isRunning();
    if (!running) {
      await service.startService();
    } else {
      service.invoke('retarget', {'executionId': executionId});
    }
  }

  /// Stop tracking. Clears the executionId and tells the service to exit.
  static Future<void> stop() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_Keys.executionId);

    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      service.invoke('stop');
    }
  }

  static Future<bool> isRunning() async {
    return FlutterBackgroundService().isRunning();
  }

  // ─────────── Background isolate entry points ───────────

  /// Top-level callback: this runs in a SEPARATE Dart isolate so it cannot
  /// access providers, controllers, or any state from the main isolate.
  /// Pulls auth token / executionId / baseUrl from SharedPreferences each
  /// tick — that way a token refresh on the main side picks up automatically.
  @pragma('vm:entry-point')
  static void _onStart(ServiceInstance service) {
    DartPluginRegistrant.ensureInitialized();

    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
      service.setForegroundNotificationInfo(
        title: 'Field tracking active',
        content: 'Sending location pings every 3 minutes',
      );
    }

    service.on('stop').listen((_) {
      service.stopSelf();
    });

    service.on('retarget').listen((event) async {
      // Re-fetch executionId immediately (already saved by start()).
      await _ping(service);
    });

    // First ping, then periodic.
    _ping(service);
    Timer.periodic(pingInterval, (_) => _ping(service));
  }

  /// iOS may invoke onBackground at most ~30s per call. We send one ping
  /// and return; the next call comes whenever iOS schedules us.
  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    await _ping(service);
    return true;
  }

  /// Read state, capture GPS, POST a ping. Failures go to the offline
  /// queue (same SharedPreferences key the in-app sync loop consumes).
  static Future<void> _ping(ServiceInstance service) async {
    final prefs = await SharedPreferences.getInstance();
    final executionId = prefs.getString(_Keys.executionId);
    if (executionId == null || executionId.isEmpty) {
      // Tracking was stopped — exit the service.
      service.stopSelf();
      return;
    }

    final token = prefs.getString(_Keys.sessionToken) ?? '';
    final baseUrl = prefs.getString(_Keys.baseUrl) ?? AppConfig.defaultBaseUrl;

    Position? loc;
    try {
      loc = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (_) {
      loc = null;
    }
    if (loc == null) return;

    final ping = <String, dynamic>{
      'latitude': loc.latitude,
      'longitude': loc.longitude,
      'accuracyM': loc.accuracy,
      'recordedAt': DateTime.now().toUtc().toIso8601String(),
      'routeExecutionId': executionId,
    };

    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      ),
    );

    try {
      await dio.post(
        '/api/v1/field-sales/locations/ping',
        data: {
          'pings': [ping],
        },
      );
    } catch (_) {
      // Enqueue offline (same shape OfflineQueue uses in the main isolate
      // so the existing sync loop will replay it once the app is online).
      await _enqueueOffline(prefs, ping);
    }
  }

  /// Mirror of OfflineQueue.enqueue using the same SharedPreferences key.
  /// Kept private + minimal so we don't reach into the main-isolate code.
  static Future<void> _enqueueOffline(
    SharedPreferences prefs,
    Map<String, dynamic> ping,
  ) async {
    const queueKey = 'field.offline.queue';
    final raw = prefs.getString(queueKey);
    final List<dynamic> existing = raw == null || raw.isEmpty
        ? <dynamic>[]
        : (jsonDecode(raw) as List);
    existing.add(<String, dynamic>{
      'id': const Uuid().v4(),
      'type': 'LOCATION_PING',
      'endpoint': '/api/v1/field-sales/locations/ping',
      'method': 'POST',
      'body': {
        'pings': [ping],
      },
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'retryCount': 0,
    });
    await prefs.setString(queueKey, jsonEncode(existing));
  }

  /// Platform sanity — currently every platform we ship uses the same
  /// code path.
  static bool get supported => Platform.isAndroid || Platform.isIOS;
}
