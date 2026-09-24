import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';

import '../configuracion/api_config.dart';
import '../red/api_client.dart';
import 'session_security_service.dart';

const _stopLocationServiceEvent = 'stopCourierLocationTracking';
const _refreshLocationSessionEvent = 'refreshCourierLocationSession';
const _locationNotificationChannelId = 'courier_location_tracking';
const _locationNotificationId = 20260903;
const _locationInterval = Duration(seconds: 10);

@pragma('vm:entry-point')
void courierLocationServiceEntryPoint(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final sessionSecurity = SessionSecurityService();
  final apiClient = ApiClient(config: ApiConfig.fromEnvironment());
  StreamSubscription<Position>? positionSubscription;
  var stopped = false;
  var sending = false;

  Future<bool> refreshSession() async {
    final values = await Future.wait<Object?>([
      sessionSecurity.readBackgroundLocationToken(),
      sessionSecurity.readBackgroundLocationUserId(),
    ]);
    final token = (values[0] as String?)?.trim() ?? '';
    final userId = values[1] as int?;
    if (token.isEmpty || userId == null || userId <= 0) return false;
    apiClient.setAccessToken(token);
    return true;
  }

  Future<void> stopTracking() async {
    if (stopped) return;
    stopped = true;
    await positionSubscription?.cancel();
    positionSubscription = null;
    await service.stopSelf();
  }

  Future<void> sendPosition(Position position) async {
    if (stopped || sending) return;
    sending = true;
    try {
      await apiClient.postJsonMap(
        '/mobile/courier/location/heartbeat',
        body: _positionPayload(position),
        authorize: true,
      );
      debugPrint(
        'Rastreo GPS en segundo plano: ubicacion enviada '
        '(${position.latitude}, ${position.longitude}).',
      );
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await sessionSecurity.clearBackgroundLocationSession();
        await stopTracking();
      } else {
        debugPrint('Rastreo GPS: fallo temporal de API: $error');
      }
    } catch (error) {
      debugPrint('Rastreo GPS: no se pudo enviar el heartbeat: $error');
    } finally {
      sending = false;
    }
  }

  service.on(_stopLocationServiceEvent).listen((_) {
    unawaited(stopTracking());
  });
  service.on(_refreshLocationSessionEvent).listen((_) {
    unawaited(refreshSession());
  });

  if (!await refreshSession()) {
    await stopTracking();
    return;
  }

  if (service is AndroidServiceInstance) {
    await service.setForegroundNotificationInfo(
      title: 'Rastreo de reparto activo',
      content: 'ChasquiApp comparte tu ubicacion durante el reparto.',
    );
  }

  final initialLocationSettings = AndroidSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 0,
    intervalDuration: _locationInterval,
    timeLimit: Duration(seconds: 30),
  );
  final streamLocationSettings = AndroidSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 0,
    intervalDuration: _locationInterval,
  );

  try {
    final currentPosition = await Geolocator.getCurrentPosition(
      locationSettings: initialLocationSettings,
    );
    await sendPosition(currentPosition);
  } catch (error) {
    debugPrint('Rastreo GPS: no se obtuvo la ubicacion inicial: $error');
  }

  if (stopped) return;
  positionSubscription =
      Geolocator.getPositionStream(
        locationSettings: streamLocationSettings,
      ).listen(
        (position) => unawaited(sendPosition(position)),
        onError: (Object error) {
          debugPrint('Rastreo GPS: fallo el flujo de ubicacion: $error');
        },
      );
}

Map<String, dynamic> _positionPayload(Position position) {
  final body = <String, dynamic>{
    'latitude': position.latitude,
    'longitude': position.longitude,
    'accuracy': position.accuracy,
    'altitude': position.altitude,
    'captured_at': position.timestamp.toUtc().toIso8601String(),
  };
  if (position.speed >= 0) body['speed'] = position.speed;
  if (position.heading >= 0 && position.heading <= 360) {
    body['heading'] = position.heading;
  }
  return body;
}

class CourierLocationHeartbeatService {
  CourierLocationHeartbeatService(this._apiClient, this._sessionSecurity);

  static const interval = _locationInterval;

  final ApiClient _apiClient;
  final SessionSecurityService _sessionSecurity;

  StreamSubscription<Position>? _positionSubscription;
  bool _enabled = false;
  bool _sending = false;

  bool get isEnabled => _enabled;

  static Future<void> initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    const channel = AndroidNotificationChannel(
      _locationNotificationChannelId,
      'Rastreo GPS de carteros',
      description: 'Ubicacion compartida durante el reparto activo',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
      showBadge: false,
    );
    final notifications = FlutterLocalNotificationsPlugin();
    await notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_package'),
      ),
    );
    await notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    await FlutterBackgroundService().configure(
      androidConfiguration: AndroidConfiguration(
        onStart: courierLocationServiceEntryPoint,
        autoStart: false,
        autoStartOnBoot: false,
        isForegroundMode: true,
        notificationChannelId: _locationNotificationChannelId,
        initialNotificationTitle: 'Rastreo de reparto activo',
        initialNotificationContent:
            'ChasquiApp esta preparando el rastreo de ubicacion.',
        foregroundServiceNotificationId: _locationNotificationId,
        foregroundServiceTypes: const [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(autoStart: false),
    );
  }

  Future<void> enable({required String token, required int userId}) async {
    if (_enabled) return;
    if (!await _ensureLocationPermission()) return;

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _sessionSecurity.saveBackgroundLocationSession(
        token: token,
        userId: userId,
      );
      final service = FlutterBackgroundService();
      if (await service.isRunning()) {
        service.invoke(_refreshLocationSessionEvent);
      } else {
        final started = await service.startService();
        if (!started) {
          await _sessionSecurity.clearBackgroundLocationSession();
          debugPrint('Rastreo GPS: Android no pudo iniciar el servicio.');
          return;
        }
      }
      _enabled = true;
      return;
    }

    await _enableInCurrentProcess();
  }

  Future<void> disable() async {
    _enabled = false;
    await _positionSubscription?.cancel();
    _positionSubscription = null;

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _sessionSecurity.clearBackgroundLocationSession();
      final service = FlutterBackgroundService();
      if (await service.isRunning()) {
        service.invoke(_stopLocationServiceEvent);
      }
    }
  }

  Future<bool> _ensureLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      debugPrint('Rastreo GPS: el servicio de ubicacion esta desactivado.');
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      debugPrint('Rastreo GPS: permiso de ubicacion no concedido.');
      return false;
    }
    return true;
  }

  Future<void> _enableInCurrentProcess() async {
    _enabled = true;
    const initialSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
      timeLimit: Duration(seconds: 30),
    );
    const streamSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
    );
    try {
      final currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: initialSettings,
      );
      await _sendPosition(currentPosition);
    } catch (error) {
      debugPrint('Rastreo GPS: no se obtuvo la ubicacion inicial: $error');
    }
    if (!_enabled) return;
    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: streamSettings).listen(
          (position) => unawaited(_sendPosition(position)),
          onError: (Object error) {
            debugPrint('Rastreo GPS: fallo el flujo de ubicacion: $error');
          },
        );
  }

  Future<void> _sendPosition(Position position) async {
    if (!_enabled || _sending) return;
    _sending = true;
    try {
      await _apiClient.postJsonMap(
        '/mobile/courier/location/heartbeat',
        body: _positionPayload(position),
        authorize: true,
      );
    } catch (error) {
      debugPrint('Rastreo GPS: no se pudo enviar el heartbeat: $error');
    } finally {
      _sending = false;
    }
  }
}
