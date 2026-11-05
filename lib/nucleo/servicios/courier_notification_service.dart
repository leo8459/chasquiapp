import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../configuracion/api_config.dart';
import '../../funcionalidades/autenticacion/dominio/utilidades/user_role_permissions.dart';
import '../red/api_client.dart';
import 'session_security_service.dart';

const _courierNotificationTask = 'checkCourierPendingNotifications';
const _courierNotificationUniqueWork = 'courierPendingNotificationsPeriodic';
const _courierNotificationTag = 'courierNotifications';
const _legacyCourierNotificationTag = 'courierNotificationsFiveMinutes';
const _courierNotificationFrequency = Duration(minutes: 15);
const _foregroundNotificationFrequency = Duration(minutes: 1);
const _courierNotificationId = 20260902;
const _managementNotificationId = 20260904;
const _managementPickupNotificationId = 20260905;
const _courierNotificationStatePrefix = 'courier_pending_notification_state';
const _managementNotificationStatePrefix =
    'management_pending_notification_state';
const _managementPickupNotificationStatePrefix =
    'management_pending_pickup_notification_state';
const _courierNotificationChannelId = 'courier_assignments_alerts_v2';
const _courierNotificationChannel = AndroidNotificationChannel(
  _courierNotificationChannelId,
  'Alertas de paquetes asignados',
  description: 'Avisos de paquetes asignados pendientes de entrega',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
  showBadge: true,
);
const _pendingNotificationDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    _courierNotificationChannelId,
    'Alertas de paquetes asignados',
    channelDescription: 'Avisos de paquetes asignados pendientes de entrega',
    importance: Importance.max,
    priority: Priority.max,
    playSound: true,
    enableVibration: true,
    visibility: NotificationVisibility.public,
    category: AndroidNotificationCategory.message,
    ticker: 'Paquetes pendientes de entrega',
  ),
);

@pragma('vm:entry-point')
void courierNotificationCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    if (taskName != _courierNotificationTask) return true;
    return CourierNotificationService.checkNow();
  });
}

class CourierNotificationService {
  CourierNotificationService(this._sessionSecurityService);

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  final SessionSecurityService _sessionSecurityService;
  static Timer? _foregroundCheckTimer;
  static Future<bool>? _checkInFlight;
  static bool _lifecycleObserverRegistered = false;
  static final _PendingNotificationLifecycleObserver _lifecycleObserver =
      _PendingNotificationLifecycleObserver();

  static Future<void> initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _registerLifecycleObserver();
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_package'),
      ),
    );
    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(_courierNotificationChannel);
    // WorkManager conserva la tarea al cerrar la app y al reiniciar el equipo.
    // Volver a registrarla también recupera la programación tras actualizar.
    final session = SessionSecurityService();
    await _restorePendingNotificationSession(session);
    await Workmanager().initialize(courierNotificationCallbackDispatcher);
    final token = (await session.readBackgroundNotificationToken())?.trim();
    if (token != null && token.isNotEmpty) {
      await schedulePeriodicCheck();
      _startForegroundChecks();
      // Además de la tarea periódica, comprueba al arrancar para que el
      // cartero no tenga que esperar al siguiente intervalo de Android.
      unawaited(checkNow());
    }
  }

  static Future<void> _restorePendingNotificationSession(
    SessionSecurityService session,
  ) async {
    try {
      final storedValues = await Future.wait<String?>([
        session.readApiAccessToken(),
        session.readAuthenticatedUserPayload(),
      ]);
      final token = storedValues[0]?.trim() ?? '';
      final userPayload = storedValues[1]?.trim() ?? '';
      if (token.isEmpty || userPayload.isEmpty) return;

      final decodedPayload = jsonDecode(userPayload);
      if (decodedPayload is! Map) return;
      final userId = _toInt(decodedPayload['id']);
      final rawRoles = decodedPayload['roles'];
      if (userId <= 0 || rawRoles is! List) return;

      final permissions = UserRolePermissions.fromRoles(
        rawRoles.map((role) => role.toString()).toSet(),
      );
      final includeCourier =
          permissions.hasCourierRole && !permissions.hasManagementRole;
      final includeManagement = permissions.hasManagementRole;
      if (!includeCourier && !includeManagement) return;

      await session.saveBackgroundNotificationSession(
        token: token,
        userId: userId,
        includeCourier: includeCourier,
        includeManagement: includeManagement,
      );
      final android = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.requestNotificationsPermission();
    } catch (error) {
      debugPrint(
        'Package notifications: no se pudo restaurar la sesión: $error',
      );
    }
  }

  static Future<void> showManualTestNotificationOnce() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (await android?.areNotificationsEnabled() == false) return;

    final prefs = await SharedPreferences.getInstance();
    const testKey = 'manual_courier_notification_test_20260902_v5';
    if (prefs.getBool(testKey) == true) return;

    await _notifications.show(
      id: 20260901,
      title: 'Prueba de notificaciones ChasquiApp',
      body: 'Las alertas de paquetes asignados están funcionando.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _courierNotificationChannelId,
          'Alertas de paquetes asignados',
          channelDescription:
              'Avisos emergentes de nuevos paquetes asignados al cartero',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          visibility: NotificationVisibility.public,
          category: AndroidNotificationCategory.message,
          ticker: 'Nuevo paquete asignado',
        ),
      ),
      payload: 'manual-test',
    );
    await prefs.setBool(testKey, true);
  }

  static Future<void> showManualPendingAlertsNotifications() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_package'),
      ),
    );
    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final permissionGranted = await android?.requestNotificationsPermission();
    if (permissionGranted == false) return;
    await android?.createNotificationChannel(_courierNotificationChannel);

    await _notifications.show(
      id: 20260906,
      title: 'Prueba: pendientes de entrega',
      body: 'Así se verá la alerta de paquetes pendientes de entrega.',
      notificationDetails: _pendingNotificationDetails,
      payload: 'manual-delivery-test',
    );
    await _notifications.show(
      id: 20260907,
      title: 'Prueba: pendientes de recojo',
      body: 'Así se verá la alerta de solicitudes pendientes de recojo.',
      notificationDetails: _pendingNotificationDetails,
      payload: 'manual-pickup-test',
    );
  }

  Future<void> enable({
    required String token,
    required int userId,
    bool includeCourier = true,
    bool includeManagement = false,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _registerLifecycleObserver();

    await _sessionSecurityService.saveBackgroundNotificationSession(
      token: token,
      userId: userId,
      includeCourier: includeCourier,
      includeManagement: includeManagement,
    );

    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final permissionGranted = await android?.requestNotificationsPermission();
    if (permissionGranted == false) return;

    if (includeCourier) {
      await showManualTestNotificationOnce();
    }
    await schedulePeriodicCheck();
    _startForegroundChecks();

    unawaited(checkNow());
  }

  static void _startForegroundChecks() {
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      _stopForegroundChecks();
      return;
    }
    _foregroundCheckTimer?.cancel();
    _foregroundCheckTimer = Timer.periodic(
      _foregroundNotificationFrequency,
      (_) => unawaited(checkNow()),
    );
  }

  static void _stopForegroundChecks() {
    _foregroundCheckTimer?.cancel();
    _foregroundCheckTimer = null;
  }

  static void _registerLifecycleObserver() {
    if (_lifecycleObserverRegistered) return;
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    _lifecycleObserverRegistered = true;
  }

  static Future<void> schedulePeriodicCheck() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    // Elimina la cadena de tareas únicas usada por versiones anteriores.
    await Workmanager().cancelByTag(_legacyCourierNotificationTag);
    await Workmanager().registerPeriodicTask(
      _courierNotificationUniqueWork,
      _courierNotificationTask,
      frequency: _courierNotificationFrequency,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(seconds: 30),
      tag: _courierNotificationTag,
    );
  }

  Future<void> disable() async {
    _stopForegroundChecks();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await Workmanager().cancelByUniqueName(_courierNotificationUniqueWork);
      await Workmanager().cancelByTag(_courierNotificationTag);
      await Workmanager().cancelByTag(_legacyCourierNotificationTag);
    }
    await _sessionSecurityService.clearBackgroundNotificationSession();
  }

  static Future<bool> checkNow() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return Future<bool>.value(true);
    }

    final inFlight = _checkInFlight;
    if (inFlight != null) return inFlight;

    final future = _checkPendingPackages();
    _checkInFlight = future;
    return future.whenComplete(() {
      if (identical(_checkInFlight, future)) {
        _checkInFlight = null;
      }
    });
  }

  static Future<bool> _checkPendingPackages() async {
    try {
      final sessionSecurity = SessionSecurityService();
      final values = await Future.wait<Object?>([
        sessionSecurity.readBackgroundNotificationToken(),
        sessionSecurity.readBackgroundNotificationUserId(),
        sessionSecurity.readBackgroundNotificationIncludesCourier(),
        sessionSecurity.readBackgroundNotificationIncludesManagement(),
      ]);
      final token = (values[0] as String?)?.trim() ?? '';
      final userId = values[1] as int?;
      final includeCourier = values[2] as bool;
      final includeManagement = values[3] as bool;
      if (token.isEmpty || userId == null || userId <= 0) {
        debugPrint('Package notifications: no hay una sesion activa guardada.');
        return true;
      }
      if (!includeCourier && !includeManagement) return true;

      await _notifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_package'),
        ),
      );

      final apiClient = ApiClient(config: ApiConfig.fromEnvironment());
      apiClient.setAccessToken(token);
      var succeeded = true;

      if (includeCourier && !includeManagement) {
        try {
          await _checkCourierPackages(apiClient, userId);
        } catch (error) {
          succeeded = false;
          debugPrint('Courier notifications: fallo la consulta: $error');
        }
      }

      if (includeManagement) {
        try {
          await _checkManagementPackages(apiClient, userId);
        } catch (error) {
          succeeded = false;
          debugPrint('Management notifications: fallo la consulta: $error');
        }
      }

      return succeeded;
    } catch (error) {
      debugPrint('Package notifications: fallo la consulta: $error');
      return false;
    }
  }

  static Future<void> _checkCourierPackages(
    ApiClient apiClient,
    int userId,
  ) async {
    final payload = await apiClient.getJsonMap(
      '/mobile/courier/pending-notifications',
      authorize: true,
    );
    final rawNotifications = payload['notifications'];
    if (rawNotifications is! List) {
      throw const FormatException('La respuesta no contiene notificaciones.');
    }

    final notifications = rawNotifications
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    final codes = notifications
        .map((item) => item['package_code']?.toString().trim() ?? '')
        .where((code) => code.isNotEmpty)
        .toList(growable: false);
    final fingerprint = codes.isEmpty
        ? ''
        : '${notifications.length}|${_sortedFingerprint(codes)}';
    final firstCode = codes.isEmpty ? '' : codes.first;
    final count = notifications.length;
    final body = count == 1 && firstCode.isNotEmpty
        ? 'Tienes asignado el paquete $firstCode.'
        : 'Tienes $count paquetes asignados pendientes de entrega.';

    await _publishIfChanged(
      stateKey: '${_courierNotificationStatePrefix}_$userId',
      notificationId: _courierNotificationId,
      fingerprint: fingerprint,
      title: 'Paquetes asignados',
      body: body,
      payload: firstCode,
    );
  }

  static Future<void> _checkManagementPackages(
    ApiClient apiClient,
    int userId,
  ) async {
    final payload = await apiClient.getJsonMap(
      '/mobile/couriers/assignments/pending',
      authorize: true,
    );
    final rawAssignments = payload['assignments'];
    if (rawAssignments is! List) {
      throw const FormatException('La respuesta no contiene asignaciones.');
    }

    final assignments = rawAssignments
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    final count = _toInt(payload['department_pending_total']);
    final department = payload['department']?.toString().trim() ?? '';
    final packageKeys = assignments
        .map((item) {
          final type = item['package_type']?.toString().trim() ?? '';
          final code = item['code']?.toString().trim() ?? '';
          return type.isEmpty || code.isEmpty ? '' : '$type:$code';
        })
        .where((key) => key.isNotEmpty)
        .toList(growable: false);
    final fingerprint = count <= 0
        ? ''
        : '$count|${_sortedFingerprint(packageKeys)}';
    final firstCode = assignments.isEmpty
        ? ''
        : assignments.first['code']?.toString().trim() ?? '';
    final area = department.isEmpty ? 'tu departamento' : department;
    final body = count == 1 && firstCode.isNotEmpty
        ? 'Tienes 1 paquete pendiente de entrega ($firstCode) en $area.'
        : 'Tienes $count paquetes pendientes de entrega en $area.';

    await _publishIfChanged(
      stateKey: '${_managementNotificationStatePrefix}_$userId',
      notificationId: _managementNotificationId,
      fingerprint: fingerprint,
      title: 'Paquetes pendientes de entrega',
      body: body,
      payload: firstCode,
    );

    final rawPickupAssignments = payload['pickup_assignments'];
    final pickupAssignments = rawPickupAssignments is List
        ? rawPickupAssignments
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false)
        : const <Map<String, dynamic>>[];
    final pickupCount = _toInt(payload['department_pending_pickup_total']);
    final pickupCodes = pickupAssignments
        .map((item) => item['code']?.toString().trim() ?? '')
        .where((code) => code.isNotEmpty)
        .toList(growable: false);
    final pickupFingerprint = pickupCount <= 0
        ? ''
        : '$pickupCount|${_sortedFingerprint(pickupCodes)}';
    final firstPickupCode = pickupCodes.isEmpty ? '' : pickupCodes.first;
    final pickupBody = pickupCount == 1 && firstPickupCode.isNotEmpty
        ? 'Tienes 1 solicitud pendiente de recojo ($firstPickupCode) en $area.'
        : 'Tienes $pickupCount solicitudes pendientes de recojo en $area.';

    await _publishIfChanged(
      stateKey: '${_managementPickupNotificationStatePrefix}_$userId',
      notificationId: _managementPickupNotificationId,
      fingerprint: pickupFingerprint,
      title: 'Solicitudes pendientes de recojo',
      body: pickupBody,
      payload: firstPickupCode,
    );
  }

  static String _sortedFingerprint(List<String> values) {
    final sortedValues = values.toSet().toList(growable: false)..sort();
    return sortedValues.join('|');
  }

  static Future<void> _publishIfChanged({
    required String stateKey,
    required int notificationId,
    required String fingerprint,
    required String title,
    required String body,
    required String payload,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    if (fingerprint.isEmpty) {
      await preferences.setString(stateKey, '');
      await _notifications.cancel(id: notificationId);
      return;
    }

    if (preferences.getString(stateKey) == fingerprint) return;

    await _notifications.show(
      id: notificationId,
      title: title,
      body: body,
      notificationDetails: _pendingNotificationDetails,
      payload: payload,
    );
    await preferences.setString(stateKey, fingerprint);
    debugPrint('Package notifications: alerta publicada: $title');
  }

  static int _toInt(dynamic value) =>
      int.tryParse(value?.toString() ?? '') ?? 0;
}

class _PendingNotificationLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      CourierNotificationService._startForegroundChecks();
      unawaited(CourierNotificationService.checkNow());
    } else {
      CourierNotificationService._stopForegroundChecks();
    }
  }
}
