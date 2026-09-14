class ApiConfig {
  const ApiConfig({required this.baseUrl});

  // API pública de producción. No usar una IP privada como valor incluido en
  // el APK: el teléfono no puede alcanzarla fuera de esa red Wi-Fi.
  static const defaultBaseUrl =
      'https://dev.correos.gob.bo:18100/chasquiapp/api';

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
