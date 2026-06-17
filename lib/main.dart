import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app/field_app.dart';
import 'src/core/location/background_location_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Configure the background location service up-front so the foreground
  // service can be started later when the salesperson kicks off a route.
  // Failure here must not block the app from running.
  try {
    await BackgroundLocationService.initialize();
  } catch (_) {
    // Plugin missing or platform unsupported — the in-app Timer fallback
    // in LocationPingTracker still keeps pings flowing while foregrounded.
  }
  runApp(const ProviderScope(child: FieldApp()));
}
