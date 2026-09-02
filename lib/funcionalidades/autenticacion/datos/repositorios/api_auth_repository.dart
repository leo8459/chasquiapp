import 'dart:convert';

import 'package:scan_agbc/nucleo/red/api_client.dart';
import 'package:scan_agbc/nucleo/servicios/session_security_service.dart';
import 'package:scan_agbc/nucleo/utilidades/user_friendly_error_mapper.dart';
import 'package:scan_agbc/funcionalidades/autenticacion/dominio/modelos/authenticated_user.dart';
import 'package:scan_agbc/funcionalidades/autenticacion/dominio/repositorios/auth_repository.dart';
import 'package:scan_agbc/funcionalidades/autenticacion/dominio/utilidades/user_role_permissions.dart';

class ApiAuthRepository extends AuthRepository {
  ApiAuthRepository(
    this._client,
    this._sessionSecurityService, {
    Future<void> Function()? onAuthenticatedUserChanged,
  }) : _onAuthenticatedUserChanged = onAuthenticatedUserChanged;

  final ApiClient _client;
  final SessionSecurityService _sessionSecurityService;
  final Future<void> Function()? _onAuthenticatedUserChanged;

  @override
  Future<AuthenticatedUser> signIn({
    required String email,
    required String password,
  }) async {
    final normalizedAlias = _normalizeAlias(email);
    final rawPassword = password;

    if (normalizedAlias.isEmpty) {
      throw StateError('Ingresa tu alias de SIOP.');
    }
    if (rawPassword.trim().isEmpty) {
      throw StateError('Ingresa tu contraseña para continuar.');
    }

    try {
      final payload = await _client.postJsonMap(
        '/mobile/auth/login',
        body: {'alias': normalizedAlias, 'password': rawPassword},
      );
      final token = payload['token']?.toString().trim() ?? '';
      if (token.isEmpty) {
        throw StateError(
          'No pudimos completar tu ingreso en este momento. Intenta nuevamente.',
        );
      }

      final userPayload = _readUserPayload(payload);
      final user = _buildAuthorizedUser(userPayload);

      _client.setAccessToken(token);
      await _onAuthenticatedUserChanged?.call();

      return user;
    } catch (error) {
      throw StateError(
        UserFriendlyErrorMapper.message(
          error,
          fallback: 'No pudimos completar tu ingreso en este momento.',
        ),
      );
    }
  }

  @override
  Future<AuthenticatedUser> authorizeRememberedAccount(String email) async {
    final normalizedAlias = _normalizeAlias(email);
    if (normalizedAlias.isEmpty) {
      throw StateError('Ingresa tu alias de SIOP.');
    }

    final storedState = await Future.wait<String?>([
      _sessionSecurityService.readApiAccessToken(),
      _sessionSecurityService.readAuthenticatedUserPayload(),
    ]);
    final storedToken = storedState[0];
    final storedUserPayload = storedState[1];
    if ((storedToken ?? '').trim().isEmpty ||
        (storedUserPayload ?? '').trim().isEmpty) {
      throw StateError(
        'La sesión guardada ya no está disponible. Vuelve a iniciar sesión.',
      );
    }

    final decodedPayload = _decodeStoredPayload(storedUserPayload!);
    final cachedAlias =
        (decodedPayload['alias'] ?? decodedPayload['email'])
            ?.toString()
            .trim()
            .toLowerCase() ??
        '';
    if (cachedAlias != normalizedAlias) {
      throw StateError(
        'La cuenta guardada no coincide con la que intentas abrir.',
      );
    }

    _client.setAccessToken(storedToken);

    try {
      final payload = await _client.getJsonMap(
        '/mobile/auth/me',
        authorize: true,
      );
      final userPayload = _readUserPayload(payload);
      final user = _buildAuthorizedUser(userPayload);
      await _sessionSecurityService.saveAuthenticatedUserPayload(
        jsonEncode(userPayload),
      );
      return user;
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        _client.setAccessToken(null);
        await _sessionSecurityService.clearAuthenticatedState();
        throw StateError('Tu sesión guardada venció. Vuelve a iniciar sesión.');
      }
      throw StateError(
        UserFriendlyErrorMapper.message(
          error,
          fallback: 'No pudimos recuperar tu sesión en este momento.',
        ),
      );
    } catch (error) {
      throw StateError(
        UserFriendlyErrorMapper.message(
          error,
          fallback: 'No pudimos recuperar tu sesión en este momento.',
        ),
      );
    }
  }

  Map<String, dynamic> _readUserPayload(Map<String, dynamic> payload) {
    final user = payload['user'];
    if (user is Map<String, dynamic>) {
      return user;
    }
    if (user is Map) {
      return user.map((key, value) => MapEntry(key.toString(), value));
    }
    throw StateError(
      'No pudimos recuperar la información de tu cuenta. Intenta nuevamente.',
    );
  }

  Map<String, dynamic> _decodeStoredPayload(String rawPayload) {
    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } on FormatException {
      throw StateError('La sesión guardada no tiene un formato válido.');
    }
    throw StateError('La sesión guardada no tiene un formato válido.');
  }

  AuthenticatedUser _buildAuthorizedUser(Map<String, dynamic> payload) {
    final userId = _toInt(payload['id']);
    if (userId <= 0) {
      throw StateError(
        'No pudimos reconocer tu cuenta. Intenta ingresar nuevamente.',
      );
    }

    final alias = _normalizeAlias(
      (payload['alias'] ?? payload['email'])?.toString() ?? '',
    );
    if (alias.isEmpty) {
      throw StateError('No pudimos reconocer el alias de tu cuenta.');
    }
    final email = _normalizeAlias(payload['email']?.toString() ?? alias);

    final roles = _readRoles(payload['roles']);
    if (roles.isEmpty) {
      throw StateError('Tu cuenta todavía no tiene acceso a esta app.');
    }

    final permissions = UserRolePermissions.fromRoles(roles);
    if (!permissions.hasRecognizedRole) {
      throw StateError(
        'Tu cuenta todavía no tiene permiso para usar esta aplicación.',
      );
    }

    final name = payload['name']?.toString().trim() ?? '';
    return AuthenticatedUser(
      id: userId,
      name: name.isEmpty ? email : name,
      alias: alias,
      email: email,
      roles: roles,
    );
  }

  Set<String> _readRoles(dynamic rawRoles) {
    if (rawRoles is! List) {
      return <String>{};
    }

    return rawRoles
        .map((role) => role.toString().trim().toLowerCase())
        .where((role) => role.isNotEmpty)
        .toSet();
  }

  int _toInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _normalizeAlias(String alias) => alias.trim().toLowerCase();
}
