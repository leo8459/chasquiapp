import 'package:flutter/material.dart';

import 'funcionalidades/autenticacion/presentacion/paginas/login_page.dart';
import 'nucleo/componentes/app_feedback_banner.dart';
import 'nucleo/inyeccion/app_services.dart';
import 'nucleo/tema/app_theme.dart';

class BaseFlutterAndroidApp extends StatefulWidget {
  const BaseFlutterAndroidApp({super.key});

  @override
  State<BaseFlutterAndroidApp> createState() => _BaseFlutterAndroidAppState();
}

class _BaseFlutterAndroidAppState extends State<BaseFlutterAndroidApp> {
  static const AssetImage _packageBoxImage = AssetImage(
    'assets/images/package_box.png',
  );

  static final AppServices _services = AppServices();
  bool _didPrecachePackageBoxImage = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didPrecachePackageBoxImage) return;
    _didPrecachePackageBoxImage = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      precacheImage(_packageBoxImage, context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ChasquiApp',
      theme: AppTheme.buildTheme(),
      scaffoldMessengerKey: appScaffoldMessengerKey,
      home: LoginPage(services: _services),
    );
  }
}
