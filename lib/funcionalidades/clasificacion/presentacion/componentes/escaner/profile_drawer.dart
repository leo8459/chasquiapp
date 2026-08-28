import 'package:flutter/material.dart';

import 'package:scan_agbc/nucleo/componentes/app_user_drawer.dart';

class ProfileDrawer extends StatelessWidget {
  const ProfileDrawer({
    super.key,
    required this.displayName,
    required this.email,
    required this.rememberSession,
    required this.useBiometric,
    required this.biometricAvailable,
    required this.onRememberSessionChanged,
    required this.onUseBiometricChanged,
    required this.onLogout,
  });

  final String displayName;
  final String email;
  final bool rememberSession;
  final bool useBiometric;
  final bool biometricAvailable;
  final ValueChanged<bool> onRememberSessionChanged;
  final ValueChanged<bool> onUseBiometricChanged;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return AppUserDrawer(
      displayName: displayName,
      email: email,
      statusLabel: 'Cuenta activa',
      statusIcon: Icons.verified_user_outlined,
      rememberSession: rememberSession,
      useBiometric: useBiometric,
      biometricAvailable: biometricAvailable,
      onRememberSessionChanged: onRememberSessionChanged,
      onUseBiometricChanged: onUseBiometricChanged,
      onLogout: () async {
        onLogout();
      },
      showLogoWatermark: true,
      infoItems: const [
        AppDrawerInfoItem(
          icon: Icons.search_rounded,
          title: 'Consulta por código',
          subtitle:
              'Busca el paquete y revisa ciudad, destinatario, teléfono y dirección.',
        ),
      ],
    );
  }
}
