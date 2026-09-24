import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../configuracion/api_config.dart';
import '../red/api_client.dart';
import 'session_security_service.dart';

const _courierNotificationTask = 'checkCourierPendingNotifications';
const _courierNotificationUniqueWork = 'courierPendingNotificationsPeriodic';
const _courierNotificationTag = 'courierNotifications';
const _legacyCourierNotificationTag = 'courierNotificationsFiveMinutes';
const _courierNotificationFrequency = Duration(minutes: 15);
const _courierNotificationChannelId = 'courier_assignments_alerts_v2';
const _courierNotificationChannel = AndroidNotificationChannel(
  _courierNotificationChannelId,
  'Alertas de paquetes asignados',
  description: 'Avisos emergentes de nuevos paquetes asignados al cartero',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
  showBadge: true,
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

  static Future<void> initialize() async {
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
    await android?.createNotificationChannel(_courierNotificationChannel);
    await Workmanager().initialize(courierNotificationCallbackDispatcher);

    // WorkManager conserva la tarea al cerrar la app y al reiniciar el equipo.
    // Volver a registrarla también recupera la programación tras actualizar.
    final session = SessionSecurityService();
    final token = (await session.readBackgroundNotificationToken())?.trim();
    if (token != null && token.isNotEmpty) {
      await schedulePeriodicCheck();
      // Además de la tarea periódica, comprueba al arrancar para que el
      // cartero no tenga que esperar al siguiente intervalo de Android.
      unawaited(checkNow());
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

  Future<void> enable({required String token, required int userId}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    await _sessionSecurityService.saveBackgroundNotificationSession(
      token: token,
      userId: userId,
    );

    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final permissionGranted = await android?.requestNotificationsPermission();
    if (permissionGranted == false) return;

    await showManualTestNotificationOnce();
    await schedulePeriodicCheck();

    unawaited(checkNow());
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
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await Workmanager().cancelByUniqueName(_courierNotificationUniqueWork);
      await Workmanager().cancelByTag(_courierNotificationTag);
      await Workmanager().cancelByTag(_legacyCourierNotificationTag);
    }
    await _sessionSecurityService.clearBackgroundNotificationSession();
  }

  static Future<bool> checkNow() async {
    try {
      final sessionSecurity = SessionSecurityService();
      final values = await Future.wait<Object?>([
        sessionSecurity.readBackgroundNotificationToken(),
        sessionSecurity.readBackgroundNotificationUserId(),
      ]);
      final token = (values[0] as String?)?.trim() ?? '';
      final userId = values[1] as int?;
      if (token.isEmpty || userId == null || userId <= 0) {
        debugPrint('Courier notifications: no hay una sesion activa guardada.');
        return true;
      }

      final apiClient = ApiClient(config: ApiConfig.fromEnvironment());
      apiClient.setAccessToken(token);
      final payload = await apiClient.getJsonMap(
        '/mobile/courier/pending-notifications',
        authorize: true,
      );
      final rawNotifications = payload['notifications'];
      if (rawNotifications is! List) {
        debugPrint('Courier notifications: respuesta sin lista de avisos.');
        return true;
      }
      debugPrint(
        'Courier notifications: ${rawNotifications.length} pendiente(s).',
      );

      await _notifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_package'),
        ),
      );

      if (rawNotifications.isEmpty) return true;

      final normalizedNotifications = rawNotifications
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
      if (normalizedNotifications.isEmpty) return true;

      final firstItem = normalizedNotifications.first;
      final firstCode = firstItem['package_code']?.toString().trim() ?? '';
      final count = normalizedNotifications.length;
      final body = count == 1 && firstCode.isNotEmpty
          ? 'Tienes asignado el paquete $firstCode.'
          : 'Tienes $count paquetes asignados pendientes de entrega.';

      await _notifications.show(
        id: 20260902,
        title: 'Paquetes asignados',
        body: body,
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
        payload: firstCode,
      );
      debugPrint('Courier notifications: alerta resumen publicada.');
      return true;
    } catch (error) {
      debugPrint('Courier notifications: fallo la consulta: $error');
      return false;
    }
  }
}
