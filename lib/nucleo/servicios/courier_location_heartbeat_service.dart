import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../red/api_client.dart';

class CourierLocationHeartbeatService {
  CourierLocationHeartbeatService(this._apiClient);

  static const interval = Duration(seconds: 10);

  final ApiClient _apiClient;

  StreamSubscription<Position>? _positionSubscription;
  bool _enabled = false;
  bool _sending = false;

  bool get isEnabled => _enabled;

  Future<void> enable() async {
    if (_enabled) {
      return;
    }

    if (!await Geolocator.isLocationServiceEnabled()) {
      debugPrint('Rastreo GPS: el servicio de ubicacion esta desactivado.');
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      debugPrint('Rastreo GPS: permiso de ubicacion no concedido.');
      return;
    }

    _enabled = true;
    final LocationSettings locationSettings =
        defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0,
            intervalDuration: interval,
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'Rastreo de reparto activo',
              notificationText:
                  'ScanAGBC esta compartiendo tu ubicacion durante el reparto.',
              notificationChannelName: 'Rastreo GPS de carteros',
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0,
          );

    // No esperar a que el repartidor se desplace: al iniciar sesión SIOP debe
    // recibir una ubicación de inmediato. El stream se mantiene después para
    // los heartbeats periódicos y las actualizaciones por movimiento.
    try {
      final currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: locationSettings,
        timeLimit: const Duration(seconds: 20),
      );
      await _sendPosition(currentPosition);
    } catch (error) {
      debugPrint('Rastreo GPS: no se pudo obtener la ubicacion inicial: $error');
    }

    if (!_enabled) return;
    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (position) => unawaited(_sendPosition(position)),
          onError: (Object error) {
            debugPrint('Rastreo GPS: fallo el flujo de ubicacion: $error');
          },
        );
  }

  Future<void> disable() async {
    _enabled = false;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  Future<void> _sendPosition(Position position) async {
    if (!_enabled || _sending) return;
    _sending = true;

    try {
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

      await _apiClient.postJsonMap(
        '/mobile/courier/location/heartbeat',
        body: body,
        authorize: true,
      );
      debugPrint(
        'Rastreo GPS: ubicacion enviada (${position.latitude}, ${position.longitude}).',
      );
    } catch (error) {
      // Un fallo puntual de GPS o red no detiene los siguientes heartbeats.
      debugPrint('Rastreo GPS: no se pudo enviar el heartbeat: $error');
    } finally {
      _sending = false;
    }
  }
}
