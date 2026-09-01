class UserFriendlyErrorMapper {
  const UserFriendlyErrorMapper._();

  static String message(
    Object? error, {
    String fallback = 'Algo no salió como esperábamos. Intenta nuevamente.',
  }) {
    final raw = _rawMessage(error);
    if (raw.isEmpty) return fallback;

    final normalized = raw.toLowerCase();

    if (_containsAny(normalized, const [
      'sesion exp',
      'sesión exp',
      'sesion termin',
      'sesión termin',
      'session_expired',
    ])) {
      return 'Tu sesión terminó. Vuelve a ingresar para continuar.';
    }

    if ((normalized.contains('usuario o contrase') &&
            normalized.contains('incorrect')) ||
        normalized.contains('invalid credentials')) {
      return 'El usuario o la contraseña no son correctos.';
    }

    if (_containsAny(normalized, const [
      'ya no esta disponible para asignar',
      'ya no está disponible para asignar',
      'package_not_available',
    ])) {
      return 'Este paquete ya fue asignado o cambió de estado. Actualiza la lista e inténtalo nuevamente.';
    }

    if (_containsAny(normalized, const [
      'asignacion ya no esta activa',
      'asignación ya no está activa',
      'assignment_not_active',
    ])) {
      return 'Esta asignación ya fue actualizada. Regresa a la lista para ver los cambios.';
    }

    if (_containsAny(normalized, const [
      'no pertenece a la ciudad',
      'package_city_mismatch',
    ])) {
      return 'Este paquete pertenece a otra ciudad y no se puede asignar aquí.';
    }

    if (_containsAny(normalized, const [
      'no se pudo conectar',
      'conexi',
      'internet',
      'timeout',
      'tiempo de espera',
      'network_unavailable',
      'request_timeout',
    ])) {
      return 'No pudimos conectarnos. Revisa tu internet e inténtalo nuevamente.';
    }

    if (_containsAny(normalized, const ['no tienes permisos', 'forbidden'])) {
      return 'Tu cuenta no tiene permiso para realizar esta acción.';
    }

    if ((normalized.contains('rol') && normalized.contains('cuenta')) ||
        normalized.contains('role_not_allowed') ||
        normalized.contains('roles_required')) {
      return 'Tu cuenta todavía no tiene acceso a esta opción.';
    }

    if (_containsAny(normalized, const [
      'usuario autenticado',
      'identificar el usuario',
      'invalid_user_id',
    ])) {
      return 'No pudimos reconocer tu cuenta. Vuelve a ingresar e intenta otra vez.';
    }

    if (_containsAny(normalized, const ['camara', 'cámara'])) {
      return 'No pudimos usar la cámara. Revisa el permiso e inténtalo nuevamente.';
    }

    if (_containsAny(normalized, const ['galeria', 'galería'])) {
      return 'No pudimos abrir la galería. Inténtalo nuevamente.';
    }

    if (normalized.contains('firma')) {
      return 'No pudimos guardar la firma. Inténtalo nuevamente.';
    }

    if (normalized.contains('foto')) {
      return 'No pudimos guardar la foto. Inténtalo nuevamente con una imagen más clara.';
    }

    if (_containsTechnicalDetails(raw, normalized)) return fallback;
    if (_isSafeBusinessMessage(normalized)) return _withFinalPunctuation(raw);

    return fallback;
  }

  static bool _containsAny(String text, List<String> values) {
    for (final value in values) {
      if (text.contains(value)) return true;
    }
    return false;
  }

  static bool _containsTechnicalDetails(String raw, String normalized) {
    if (RegExp(r'^[A-Z][A-Z0-9_]{2,}$').hasMatch(raw)) return true;

    return _containsAny(normalized, const [
      'sqlstate',
      'exception',
      'stack trace',
      'backend',
      'token',
      'json',
      'socket',
      'handshake',
      'status code',
      'base de datos',
      'database',
      'postgres',
      'redis',
      'tabla ',
      'columna ',
      'undefined',
      'is not a subtype',
      'bad state',
      'formato inesperado',
      'respuesta inesperada',
    ]);
  }

  static bool _isSafeBusinessMessage(String normalized) {
    const safePrefixes = [
      'debes ',
      'ingresa ',
      'ingrese ',
      'escribe ',
      'revisa ',
      'selecciona ',
      'solo se permiten ',
      'usa ',
      'use ',
      'este paquete ',
      'el paquete ',
      'la asignacion ',
      'la asignación ',
      'no encontramos ',
      'no pudimos ',
      'tu cuenta ',
      'tu usuario ',
      'cada nombre ',
      'el nombre ',
      'el campo ',
      'la foto ',
      'la fecha ',
    ];

    for (final prefix in safePrefixes) {
      if (normalized.startsWith(prefix)) return true;
    }
    return false;
  }

  static String _withFinalPunctuation(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty || RegExp(r'[.!?]$').hasMatch(trimmed)) return trimmed;
    return '$trimmed.';
  }

  static String _rawMessage(Object? error) {
    if (error == null) return '';

    var raw = error.toString().trim();
    for (final prefix in const [
      'Bad state: ',
      'Exception: ',
      'ApiException: ',
    ]) {
      if (raw.startsWith(prefix)) {
        raw = raw.substring(prefix.length).trim();
      }
    }
    return raw;
  }
}
