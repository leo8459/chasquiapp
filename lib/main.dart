import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'nucleo/servicios/courier_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CourierNotificationService.initialize();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const BaseFlutterAndroidApp());
  if (const bool.fromEnvironment('SEND_NOTIFICATION_TEST')) {
    unawaited(
      Future<void>.delayed(
        const Duration(seconds: 2),
        CourierNotificationService.showManualTestNotificationOnce,
      ),
    );
  }
}
