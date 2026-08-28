import 'package:flutter/material.dart';

import 'package:scan_agbc/nucleo/inyeccion/app_services.dart';
import 'package:scan_agbc/nucleo/componentes/app_user_drawer.dart';
import 'package:scan_agbc/funcionalidades/autenticacion/presentacion/paginas/login_page.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.displayName,
    required this.email,
    required this.modeLabel,
    required this.modeIcon,
    required this.rememberSession,
    required this.useBiometric,
    required this.biometricAvailable,
    required this.onRememberSessionChanged,
    required this.onUseBiometricChanged,
    required this.onLogout,
    required this.services,
    this.infoItems = const [
      AppDrawerInfoItem(
        icon: Icons.search_rounded,
        title: 'Consulta por código',
        subtitle:
            'Busca el paquete y revisa ciudad, destinatario, teléfono y dirección.',
      ),
    ],
  });

  final String displayName;
  final String email;
  final String modeLabel;
  final IconData modeIcon;
  final bool rememberSession;
  final bool useBiometric;
  final bool biometricAvailable;
  final ValueChanged<bool> onRememberSessionChanged;
  final ValueChanged<bool> onUseBiometricChanged;
  final Future<void> Function() onLogout;
  final AppServices services;
  final List<AppDrawerInfoItem> infoItems;

  @override
  Widget build(BuildContext context) {
    return AppUserDrawer(
      displayName: displayName,
      email: email,
      statusLabel: modeLabel,
      statusIcon: modeIcon,
      rememberSession: rememberSession,
      useBiometric: useBiometric,
      biometricAvailable: biometricAvailable,
      onRememberSessionChanged: onRememberSessionChanged,
      onUseBiometricChanged: onUseBiometricChanged,
      onLogout: () async {
        Navigator.of(context).pop();
        await onLogout();
        if (!context.mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => LoginPage(services: services)),
          (route) => false,
        );
      },
      infoItems: infoItems,
    );
  }
}
