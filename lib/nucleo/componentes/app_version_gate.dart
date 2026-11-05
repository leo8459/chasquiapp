import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../red/api_client.dart';
import '../servicios/app_version.dart';
import '../tema/app_theme.dart';

enum _VersionStatus { checking, allowed, updateRequired, unavailable }

class AppVersionGate extends StatefulWidget {
  const AppVersionGate({super.key, required this.client, required this.child});

  final ApiClient client;
  final Widget child;

  @override
  State<AppVersionGate> createState() => _AppVersionGateState();
}

class _AppVersionGateState extends State<AppVersionGate>
    with WidgetsBindingObserver {
  _VersionStatus _status = _VersionStatus.checking;
  AppVersionRequirement? _requirement;
  String? _installedVersion;
  String? _downloadError;
  bool _unlockedOnce = false;
  bool _checking = false;
  bool _openingDownload = false;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.client.requiredUpdate.addListener(_handleServerRejection);
    unawaited(_checkVersion());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.client.requiredUpdate.removeListener(_handleServerRejection);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_checkVersion());
  }

  void _handleServerRejection() {
    final payload = widget.client.requiredUpdate.value;
    if (payload == null || !mounted) return;
    _requestId++;
    try {
      final requirement = AppVersionRequirement.fromJson(payload);
      setState(() {
        _requirement = requirement;
        _status = _VersionStatus.updateRequired;
      });
    } catch (_) {
      setState(() => _status = _VersionStatus.unavailable);
    }
  }

  Future<void> _checkVersion() async {
    if (_checking) return;
    _checking = true;
    final requestId = ++_requestId;
    setState(() => _status = _VersionStatus.checking);
    try {
      final installedVersion = await InstalledAppVersion.read();
      final payload = await widget.client.getJsonMap('/mobile/app-version');
      final requirement = AppVersionRequirement.fromJson(payload);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _installedVersion = installedVersion;
        _requirement = requirement;
        _status = installedVersion == requirement.version
            ? _VersionStatus.allowed
            : _VersionStatus.updateRequired;
        if (_status == _VersionStatus.allowed) _unlockedOnce = true;
      });
    } catch (_) {
      if (mounted && requestId == _requestId) {
        setState(() => _status = _VersionStatus.unavailable);
      }
    } finally {
      _checking = false;
    }
  }

  Future<void> _download() async {
    final requirement = _requirement;
    if (requirement == null || _openingDownload) return;
    setState(() {
      _openingDownload = true;
      _downloadError = null;
    });
    try {
      final opened = await launchUrl(
        requirement.downloadUri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw StateError('No se abrió el enlace.');
    } catch (_) {
      if (mounted) {
        setState(() {
          _downloadError =
              'No se pudo abrir el navegador. Copia el enlace y ábrelo manualmente.';
        });
      }
    } finally {
      if (mounted) setState(() => _openingDownload = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _status != _VersionStatus.allowed;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_unlockedOnce)
          ExcludeSemantics(
            excluding: blocked,
            child: ExcludeFocus(
              excluding: blocked,
              child: AbsorbPointer(absorbing: blocked, child: widget.child),
            ),
          )
        else
          const DecoratedBox(decoration: AppTheme.loginPageDecoration),
        if (blocked) ...[
          const ModalBarrier(dismissible: false, color: Colors.black54),
          AlertDialog(
            title: Text(switch (_status) {
              _VersionStatus.checking => 'Comprobando versión',
              _VersionStatus.updateRequired => 'Actualización obligatoria',
              _ => 'No se pudo comprobar la versión',
            }),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_status == _VersionStatus.checking)
                    const Center(child: CircularProgressIndicator())
                  else if (_status == _VersionStatus.updateRequired) ...[
                    const Text(
                      'Para ingresar a ChasquiApp debes descargar e instalar la versión autorizada.',
                    ),
                    const SizedBox(height: 16),
                    if (_installedVersion != null)
                      Text('Tu versión: $_installedVersion'),
                    Text('Versión requerida: ${_requirement!.version}'),
                    const SizedBox(height: 16),
                    Text(_requirement!.downloadUri.toString()),
                    TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(
                            text: _requirement!.downloadUri.toString(),
                          ),
                        );
                        if (mounted) {
                          setState(() => _downloadError = 'Enlace copiado.');
                        }
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Copiar enlace'),
                    ),
                    if (_downloadError != null) ...[
                      const SizedBox(height: 12),
                      Text(_downloadError!),
                    ],
                  ] else
                    const Text(
                      'Revisa tu conexión e intenta nuevamente. Necesitamos comprobar la versión antes de continuar.',
                    ),
                ],
              ),
            ),
            actions: [
              if (_status != _VersionStatus.checking)
                TextButton(
                  onPressed: _checkVersion,
                  child: Text(
                    _status == _VersionStatus.updateRequired
                        ? 'Volver a comprobar'
                        : 'Reintentar',
                  ),
                ),
              if (_status == _VersionStatus.updateRequired)
                FilledButton.icon(
                  onPressed: _openingDownload ? null : _download,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Descargar actualización'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
