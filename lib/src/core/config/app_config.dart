import 'package:flutter/foundation.dart';

class AppConfig {
  const AppConfig._();

  static const appName = 'Katasticho Field';

  static String get defaultBaseUrl {
    const envUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (envUrl.isNotEmpty) return envUrl;
    if (kIsWeb) {
      return Uri.base.origin;
    }
    return 'http://localhost:8080';
  }

  static const defaultEnv = String.fromEnvironment('ENV', defaultValue: 'dev');
}
