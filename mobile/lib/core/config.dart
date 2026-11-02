class AppConfig {
  static const mock = bool.fromEnvironment('USE_MOCK', defaultValue: false);
  static const _baseUrlOverride = String.fromEnvironment('API_BASE_URL');
  static String get baseUrl => _baseUrlOverride.isNotEmpty
      ? _baseUrlOverride
      : 'http://39.96.84.51/api';
}
