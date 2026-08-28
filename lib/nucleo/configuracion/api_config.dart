class ApiConfig {
  const ApiConfig({required this.baseUrl});

  static const defaultBaseUrl = 'http://127.0.0.1:8001/api';

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
