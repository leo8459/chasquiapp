import 'package:scan_agbc/nucleo/red/api_client.dart';

class UserFriendlyErrorMapper {
  const UserFriendlyErrorMapper._();

  static String message(
    Object? error, {
    String fallback = 'Algo no salió como esperábamos. Intenta nuevamente.',
  }) {
    if (error is ApiException) {
      final apiMessage = _messageForApiException(error);
      if (apiMessage != null) return apiMessage;
    }

    final raw = _rawMessage(error);
    if (raw.isEmpty) return fallback;

    final normalized = raw.toLowerCase();

    if (_containsAny(normalized, const [
      'url base de la api no fue configurada',
      'api_base_url',
    ])) {
      return 'La app no tiene configurada la direcci\u00f3n del servidor. Contacta al administrador.';
    }

    if ((normalized.contains('el usuario o la contrase') ||
            normalized.contains('el alias o la contrase')) &&
        normalized.contains('no son correctos')) {
      return 'El alias o la contrase\u00f1a no son correctos.';
    }

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

    if (normalized.contains('fecha') &&
        _containsAny(normalized, const ['entrega', 'hora', 'formato'])) {
      return 'La fecha u hora de entrega no es válida. Selecciónala nuevamente e intenta guardar.';
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

  static String? _messageForApiException(ApiException error) {
    switch (error.code?.trim().toUpperCase()) {
      case 'INVALID_CREDENTIALS':
        return 'El alias o la contrase\u00f1a no son correctos.';
      case 'ALIAS_REQUIRED':
        return 'Ingresa tu alias de SIOP.';
      case 'PASSWORD_REQUIRED':
        return 'Ingresa tu contrase\u00f1a.';
      case 'ROLE_NOT_ALLOWED':
        return 'Tu cuenta no tiene un rol autorizado para usar esta app. Contacta al administrador.';
      case 'SIOP_LOGIN_NOT_CONFIGURED':
        return 'El acceso a SIOP no est\u00e1 configurado en el servidor. Contacta al administrador.';
      case 'SIOP_LOGIN_UNAVAILABLE':
        return 'El servidor no pudo conectarse con SIOP. Intenta nuevamente m\u00e1s tarde.';
      case 'SIOP_LOGIN_TOKEN_INVALID':
        return 'La autorizaci\u00f3n del servidor para conectarse con SIOP necesita renovarse. Contacta al administrador.';
      case 'SIOP_LOGIN_RATE_LIMITED':
        return 'Hubo demasiados intentos de ingreso. Espera un momento antes de volver a intentarlo.';
      case 'SIOP_LOGIN_VALIDATION_ERROR':
        return 'SIOP no pudo validar los datos. Revisa tu alias y contrase\u00f1a e intenta nuevamente.';
      case 'SIOP_LOGIN_INVALID_RESPONSE':
        return 'SIOP devolvi\u00f3 una respuesta inesperada. Contacta al administrador.';
      case 'SIOP_LOGIN_FAILED':
        return 'SIOP no pudo completar el ingreso en este momento. Intenta m\u00e1s tarde.';
      case 'SIOP_USER_ID_MISSING':
        return 'SIOP valid\u00f3 el ingreso, pero no devolvi\u00f3 los datos necesarios de tu cuenta. Contacta al administrador.';
      case 'MOBILE_API_UNAVAILABLE':
        return 'El servidor tuvo un problema al procesar el ingreso. Intenta nuevamente y, si persiste, contacta al administrador.';
      case 'NETWORK_UNAVAILABLE':
        return 'No se pudo conectar con el servidor de la app. Revisa tu conexi\u00f3n y vuelve a intentarlo.';
      case 'REQUEST_TIMEOUT':
        return 'El servidor tard\u00f3 demasiado en responder. Intenta nuevamente en unos momentos.';
      case 'TLS_HANDSHAKE_ERROR':
        return 'No se pudo establecer una conexi\u00f3n segura con el servidor. Contacta al administrador si el problema contin\u00faa.';
      case 'INVALID_RESPONSE':
      case 'UNEXPECTED_PAYLOAD':
        return 'El servidor devolvi\u00f3 una respuesta inv\u00e1lida. Intenta m\u00e1s tarde y contacta al administrador si persiste.';
      case 'SESSION_EXPIRED':
        return 'Tu sesi\u00f3n termin\u00f3. Vuelve a ingresar para continuar.';
      default:
        return null;
    }
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
      'la app no tiene configurada',
      'el alias o la contrase',
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
