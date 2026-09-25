import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'nucleo/servicios/courier_notification_service.dart';
import 'nucleo/servicios/courier_location_heartbeat_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BaseFlutterAndroidApp());
  unawaited(_initializePlatformServices());
  if (const bool.fromEnvironment('SEND_NOTIFICATION_TEST')) {
    unawaited(
      Future<void>.delayed(
        const Duration(seconds: 2),
        CourierNotificationService.showManualTestNotificationOnce,
      ),
    );
  }
}

Future<void> _initializePlatformServices() async {
  try {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]).timeout(const Duration(seconds: 10));
  } catch (error, stackTrace) {
    debugPrint('No se pudo fijar la orientacion de pantalla: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  try {
    await CourierNotificationService.initialize().timeout(
      const Duration(seconds: 15),
    );
  } catch (error, stackTrace) {
    debugPrint('No se pudieron inicializar las notificaciones: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  try {
    await CourierLocationHeartbeatService.initialize().timeout(
      const Duration(seconds: 15),
    );
  } catch (error, stackTrace) {
    debugPrint('No se pudo inicializar el rastreo de ubicacion: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}
