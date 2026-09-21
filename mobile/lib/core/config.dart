class AppConfig {
  static const mock = bool.fromEnvironment('USE_MOCK', defaultValue: true);
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://localhost:8443/api',
  );
}
