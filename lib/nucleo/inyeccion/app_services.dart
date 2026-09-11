import 'dart:convert';

import 'package:scan_agbc/nucleo/configuracion/api_config.dart';
import 'package:scan_agbc/nucleo/red/api_client.dart';
import 'package:scan_agbc/nucleo/servicios/biometric_auth_service.dart';
import 'package:scan_agbc/nucleo/servicios/courier_notification_service.dart';
import 'package:scan_agbc/nucleo/servicios/session_security_service.dart';
import 'package:scan_agbc/funcionalidades/autenticacion/datos/repositorios/api_auth_repository.dart';
import 'package:scan_agbc/funcionalidades/autenticacion/dominio/modelos/authenticated_user.dart';
import 'package:scan_agbc/funcionalidades/autenticacion/dominio/repositorios/auth_repository.dart';
import 'package:scan_agbc/funcionalidades/bitacoras/datos/repositorios/api_bitacora_repository.dart';
import 'package:scan_agbc/funcionalidades/bitacoras/dominio/repositorios/bitacora_repository.dart';
import 'package:scan_agbc/funcionalidades/gasolina/datos/repositorios/api_gasolina_repository.dart';
import 'package:scan_agbc/funcionalidades/gasolina/dominio/repositorios/gasolina_repository.dart';
import 'package:scan_agbc/funcionalidades/mantenimiento/datos/repositorios/api_mantenimiento_repository.dart';
import 'package:scan_agbc/funcionalidades/mantenimiento/dominio/repositorios/mantenimiento_repository.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/datos/repositorios/api_package_tracking_repository.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/repositorios/package_tracking_repository.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/datos/repositorios/api_scanner_repository.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/dominio/repositorios/scanner_repository.dart';

class AppServices {
  factory AppServices({
    SessionSecurityService? sessionSecurityService,
    BiometricAuthService? biometricAuthService,
    ApiConfig? apiConfig,
    ApiClient? apiClient,
    AuthRepository? authRepository,
    PackageTrackingRepository? packageTrackingRepository,
    BitacoraRepository? bitacoraRepository,
    GasolinaRepository? gasolinaRepository,
    MantenimientoRepository? mantenimientoRepository,
    ScanRepository? scannerRepository,
  }) {
    final resolvedSessionSecurityService =
        sessionSecurityService ?? SessionSecurityService();
    final resolvedApiConfig = apiConfig ?? ApiConfig.fromEnvironment();
    final resolvedApiClient = apiClient ?? ApiClient(config: resolvedApiConfig);
    final resolvedCourierNotificationService = CourierNotificationService(
      resolvedSessionSecurityService,
    );
    final resolvedPackageTrackingRepository =
        packageTrackingRepository ??
        ApiPackageTrackingRepository(resolvedApiClient);
    final resolvedScannerRepository =
        scannerRepository ?? ApiScannerRepository(resolvedApiClient);
    return AppServices._(
      sessionSecurityService: resolvedSessionSecurityService,
      biometricAuthService: biometricAuthService ?? BiometricAuthService(),
      authRepository:
          authRepository ??
          ApiAuthRepository(
            resolvedApiClient,
            resolvedSessionSecurityService,
            onAuthenticatedUserChanged: () => _clearOperationalCaches(
              sessionSecurityService: resolvedSessionSecurityService,
              packageTrackingRepository: resolvedPackageTrackingRepository,
              scannerRepository: resolvedScannerRepository,
            ),
          ),
      packageTrackingRepository: resolvedPackageTrackingRepository,
      bitacoraRepository:
          bitacoraRepository ?? ApiBitacoraRepository(resolvedApiClient),
      gasolinaRepository:
          gasolinaRepository ?? ApiGasolinaRepository(resolvedApiClient),
      mantenimientoRepository:
          mantenimientoRepository ??
          ApiMantenimientoRepository(resolvedApiClient),
      scannerRepository: resolvedScannerRepository,
      apiConfig: resolvedApiConfig,
      apiClient: resolvedApiClient,
      courierNotificationService: resolvedCourierNotificationService,
    );
  }

  const AppServices._({
    required this.sessionSecurityService,
    required this.biometricAuthService,
    required this.authRepository,
    required this.packageTrackingRepository,
    required this.bitacoraRepository,
    required this.gasolinaRepository,
    required this.mantenimientoRepository,
    required this.scannerRepository,
    required this.apiConfig,
    required this.apiClient,
    required this.courierNotificationService,
  });

  final SessionSecurityService sessionSecurityService;
  final BiometricAuthService biometricAuthService;
  final AuthRepository authRepository;
  final PackageTrackingRepository packageTrackingRepository;
  final BitacoraRepository bitacoraRepository;
  final GasolinaRepository gasolinaRepository;
  final MantenimientoRepository mantenimientoRepository;
  final ScanRepository scannerRepository;
  final ApiConfig apiConfig;
  final ApiClient apiClient;
  final CourierNotificationService courierNotificationService;

  Future<void> activateCourierNotifications(AuthenticatedUser user) async {
    final token = apiClient.currentAccessToken?.trim() ?? '';
    if (token.isEmpty) return;
    await courierNotificationService.enable(token: token, userId: user.id);
  }

  Future<void> persistRememberedAuthState(AuthenticatedUser user) async {
    final token = apiClient.currentAccessToken;
    if (token == null || token.isEmpty) {
      return;
    }

    await sessionSecurityService.saveAuthenticatedState(
      token: token,
      userPayload: jsonEncode({
        'id': user.id,
        'name': user.name,
        'alias': user.alias,
        'email': user.email,
        'roles': user.roles.toList(),
      }),
    );
  }

  Future<void> clearActiveSession() async {
    await courierNotificationService.disable();
    apiClient.setAccessToken(null);
    await sessionSecurityService.clearAuthenticatedState();
    await _clearOperationalCaches(
      sessionSecurityService: sessionSecurityService,
      packageTrackingRepository: packageTrackingRepository,
      scannerRepository: scannerRepository,
    );
  }

  static Future<void> _clearOperationalCaches({
    required SessionSecurityService sessionSecurityService,
    required PackageTrackingRepository packageTrackingRepository,
    required ScanRepository scannerRepository,
  }) async {
    if (packageTrackingRepository is ApiPackageTrackingRepository) {
      packageTrackingRepository.clearMemoryCache();
    }
    if (scannerRepository is ApiScannerRepository) {
      scannerRepository.clearMemoryCache();
    }
    await Future.wait([
      sessionSecurityService.clearCachedOperationalData(),
      ApiPackageTrackingRepository.clearLocalCache(),
      ApiScannerRepository.clearLocalCache(),
    ]);
  }
}
