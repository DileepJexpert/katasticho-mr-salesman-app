class AppConfig {
  const AppConfig._();

  static const appName = 'Katasticho Field';
  static const defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );

  static const defaultEnv = String.fromEnvironment('ENV', defaultValue: 'dev');
}
