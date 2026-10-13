import 'package:flutter/foundation.dart';

class AppConfig {
  static const mock = bool.fromEnvironment('USE_MOCK', defaultValue: false);
  static const _baseUrlOverride = String.fromEnvironment('API_BASE_URL');
  static String get baseUrl => _baseUrlOverride.isNotEmpty
      ? _baseUrlOverride
      : !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? 'http://10.0.2.2:8080/api'
      : 'http://localhost:8080/api';
}
