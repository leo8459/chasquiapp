import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'funcionalidades/autenticacion/presentacion/paginas/login_page.dart';
import 'nucleo/componentes/app_feedback_banner.dart';
import 'nucleo/inyeccion/app_services.dart';
import 'nucleo/tema/app_theme.dart';

class BaseFlutterAndroidApp extends StatefulWidget {
  const BaseFlutterAndroidApp({super.key});

  @override
  State<BaseFlutterAndroidApp> createState() => _BaseFlutterAndroidAppState();
}

class _BaseFlutterAndroidAppState extends State<BaseFlutterAndroidApp>
    with WidgetsBindingObserver {
  static const AssetImage _packageBoxImage = AssetImage(
    'assets/images/package_box.png',
  );

  static final AppServices _services = AppServices();
  bool _didPrecachePackageBoxImage = false;
  Future<_VersionGateResult>? _versionCheck;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _versionCheck = _checkMinimumVersion();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _retryVersionCheck();
  }

  Future<_VersionGateResult> _checkMinimumVersion() async {
    try {
      final installed = await PackageInfo.fromPlatform();
      final policy = await _services.apiClient.getJsonMap('mobile/app-version');
      final minimumVersion = policy['minimum_version']?.toString().trim() ?? '';
      final downloadUrl = policy['download_url']?.toString().trim() ?? '';
      if (minimumVersion.isEmpty || downloadUrl.isEmpty) {
        throw const FormatException('La política de versión está incompleta.');
      }
      return _VersionGateResult(
        currentVersion: installed.version,
        minimumVersion: minimumVersion,
        downloadUrl: downloadUrl,
        mustUpdate: _compareVersions(installed.version, minimumVersion) < 0,
      );
    } catch (_) {
      return const _VersionGateResult(error: true);
    }
  }

  int _compareVersions(String current, String minimum) {
    List<int> parts(String version) => version
        .split('+')
        .first
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
    final left = parts(current);
    final right = parts(minimum);
    for (
      var i = 0;
      i < (left.length > right.length ? left.length : right.length);
      i++
    ) {
      final a = i < left.length ? left[i] : 0;
      final b = i < right.length ? right[i] : 0;
      if (a != b) return a.compareTo(b);
    }
    return 0;
  }

  void _retryVersionCheck() {
    setState(() => _versionCheck = _checkMinimumVersion());
  }

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
      home: FutureBuilder<_VersionGateResult>(
        future: _versionCheck,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const _VersionGateMessage(
              message: 'Verificando la versión de ChasquiApp…',
            );
          }
          final result = snapshot.data!;
          if (result.error) {
            return _VersionGateMessage(
              message:
                  'Conéctate a internet para verificar si hay una actualización.',
              onRetry: _retryVersionCheck,
            );
          }
          if (result.mustUpdate) {
            return _VersionGateMessage(
              message:
                  'Debes actualizar ChasquiApp para continuar. Versión instalada: ${result.currentVersion}. Versión requerida: ${result.minimumVersion}.',
              buttonLabel: 'Descargar actualización',
              onAction: () async {
                final uri = Uri.tryParse(result.downloadUrl);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            );
          }
          return LoginPage(services: _services);
        },
      ),
    );
  }
}

class _VersionGateResult {
  const _VersionGateResult({
    this.currentVersion = '',
    this.minimumVersion = '',
    this.downloadUrl = '',
    this.mustUpdate = false,
    this.error = false,
  });

  final String currentVersion;
  final String minimumVersion;
  final String downloadUrl;
  final bool mustUpdate;
  final bool error;
}

class _VersionGateMessage extends StatelessWidget {
  const _VersionGateMessage({
    required this.message,
    this.onRetry,
    this.onAction,
    this.buttonLabel = 'Reintentar',
  });

  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onAction;
  final String buttonLabel;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.system_update_alt, size: 56),
              const SizedBox(height: 20),
              const Text(
                'ChasquiApp',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              if (onRetry != null || onAction != null) ...[
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: onAction ?? onRetry,
                  child: Text(buttonLabel),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
