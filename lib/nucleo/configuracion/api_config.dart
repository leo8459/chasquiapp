class ApiConfig {
  const ApiConfig({required this.baseUrl});

  // Dirección de la laptop dentro de la red Wi-Fi. En Android, 127.0.0.1
  // apunta al teléfono y solo funciona mediante `adb reverse` por USB.
  static const defaultBaseUrl = 'http://10.10.100.19:8001/api';

  final String baseUrl;

  static ApiConfig fromEnvironment() {
    return const ApiConfig(
      baseUrl: String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: defaultBaseUrl,
      ),
    );
  }

  Uri get baseUri {
    final normalized = baseUrl.trim();
    if (normalized.isEmpty) {
      throw StateError(
        'La URL base de la API no fue configurada. '
        'Ejecuta la app con --dart-define=API_BASE_URL=<url>.',
      );
    }

    final withTrailingSlash = normalized.endsWith('/')
        ? normalized
        : '$normalized/';
    return Uri.parse(withTrailingSlash);
  }
}
