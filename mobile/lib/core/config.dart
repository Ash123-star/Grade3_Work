class AppConfig {
  static const mock = bool.fromEnvironment('USE_MOCK', defaultValue: false);
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080/api',
  );
}
