import 'package:flutter/material.dart';

import 'package:scan_agbc/nucleo/tema/app_theme.dart';

class AppDrawerInfoItem {
  const AppDrawerInfoItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
}

class AppDrawerActionItem {
  const AppDrawerActionItem({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
}

class AppUserDrawer extends StatelessWidget {
  const AppUserDrawer({
    super.key,
    required this.displayName,
    required this.email,
    required this.statusLabel,
    required this.statusIcon,
    required this.rememberSession,
    required this.useBiometric,
    required this.biometricAvailable,
    required this.onRememberSessionChanged,
    required this.onUseBiometricChanged,
    required this.onLogout,
    this.infoItems = const <AppDrawerInfoItem>[],
    this.actionItems = const <AppDrawerActionItem>[],
    this.showLogoWatermark = false,
    this.logoutLabel = 'Cerrar sesión',
  });

  final String displayName;
  final String email;
  final String statusLabel;
  final IconData statusIcon;
  final bool rememberSession;
  final bool useBiometric;
  final bool biometricAvailable;
  final ValueChanged<bool> onRememberSessionChanged;
  final ValueChanged<bool> onUseBiometricChanged;
  final Future<void> Function() onLogout;
  final List<AppDrawerInfoItem> infoItems;
  final List<AppDrawerActionItem> actionItems;
  final bool showLogoWatermark;
  final String logoutLabel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Drawer(
      width: 285,
      backgroundColor: const Color(0xFFFFF3CF),
      child: SafeArea(
        child: Container(
          decoration: const BoxDecoration(gradient: AppTheme.drawerGradient),
          child: Stack(
            children: [
              if (showLogoWatermark)
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 14,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: 0.25,
                      child: Image.asset(
                        'assets/images/logo.png',
                        height: 64,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ListView(
                padding: EdgeInsets.fromLTRB(
                  12,
                  12,
                  12,
                  showLogoWatermark ? 96 : 24,
                ),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.yellow,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.blue),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x331B305F),
                          blurRadius: 14,
                          offset: Offset(0, 7),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const CircleAvatar(
                              radius: 23,
                              backgroundColor: AppTheme.blue,
                              child: Icon(
                                Icons.person_rounded,
                                color: AppTheme.yellowField,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.titleSmall?.copyWith(
                                      color: AppTheme.blue,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    email,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.bodySmall?.copyWith(
                                      color: AppTheme.blue,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFE9A8),
                            borderRadius: AppTheme.radiusSmall,
                            border: Border.all(color: const Color(0x801B305F)),
                          ),
                          child: Row(
                            children: [
                              Icon(statusIcon, size: 16, color: AppTheme.blue),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  statusLabel,
                                  style: textTheme.labelSmall?.copyWith(
                                    color: AppTheme.blue,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const _DrawerSectionTitle(
                    icon: Icons.security_outlined,
                    title: 'Seguridad',
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: AppTheme.buildSoftCardDecoration(
                      backgroundColor: const Color(0x80FFF1CF),
                      borderRadius: BorderRadius.circular(14),
                      borderColor: AppTheme.softBorder,
                    ),
                    child: Column(
                      children: [
                        _DrawerSwitchTile(
                          icon: Icons.schedule_rounded,
                          label: 'Sesión activa hasta cerrar sesión',
                          value: true,
                          onChanged: null,
                        ),
                        const Divider(height: 8, color: Color(0x331B305F)),
                        _DrawerSwitchTile(
                          icon: biometricAvailable
                              ? Icons.fingerprint_rounded
                              : Icons.block_rounded,
                          label: biometricAvailable
                              ? 'Usar huella para ingresar'
                              : 'Huella no disponible',
                          value:
                              rememberSession &&
                              biometricAvailable &&
                              useBiometric,
                          onChanged: rememberSession && biometricAvailable
                              ? onUseBiometricChanged
                              : null,
                        ),
                      ],
                    ),
                  ),
                  if (actionItems.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const _DrawerSectionTitle(
                      icon: Icons.apps_rounded,
                      title: 'Navegación',
                    ),
                    const SizedBox(height: 8),
                    ...actionItems.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _DrawerNavigationTile(item: item),
                      ),
                    ),
                  ],
                  if (infoItems.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const _DrawerSectionTitle(
                      icon: Icons.info_outline_rounded,
                      title: 'Uso rapido',
                    ),
                    const SizedBox(height: 8),
                    ...infoItems.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _DrawerInfoCard(item: item),
                      ),
                    ),
                  ],
                  const SizedBox(height: 2),
                  const _DrawerSectionTitle(
                    icon: Icons.logout_rounded,
                    title: 'Sesión',
                  ),
                  const SizedBox(height: 8),
                  _DrawerActionButton(
                    icon: Icons.logout_rounded,
                    label: logoutLabel,
                    onTap: onLogout,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerNavigationTile extends StatelessWidget {
  const _DrawerNavigationTile({required this.item});

  final AppDrawerActionItem item;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          decoration: AppTheme.buildSoftCardDecoration(
            backgroundColor: const Color(0xCCFFF1CF),
            borderRadius: BorderRadius.circular(14),
            borderColor: AppTheme.softBorder,
          ),
          child: Row(
            children: [
              Icon(item.icon, color: AppTheme.blue, size: 22),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  item.title,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: AppTheme.blue),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.blue,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerSectionTitle extends StatelessWidget {
  const _DrawerSectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.blue),
        const SizedBox(width: 7),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(color: AppTheme.blue),
        ),
      ],
    );
  }
}

class _DrawerInfoCard extends StatelessWidget {
  const _DrawerInfoCard({required this.item});

  final AppDrawerInfoItem item;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.buildSoftCardDecoration(
        backgroundColor: const Color(0x80FFF1CF),
        borderRadius: BorderRadius.circular(14),
        borderColor: AppTheme.softBorder,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.blue,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item.icon, color: AppTheme.yellowField, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: textTheme.titleSmall?.copyWith(color: AppTheme.blue),
                ),
                const SizedBox(height: 4),
                Text(
                  item.subtitle,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppTheme.blueDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerSwitchTile extends StatelessWidget {
  const _DrawerSwitchTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      activeThumbColor: AppTheme.blue,
      activeTrackColor: const Color(0xFFF5D97B),
      inactiveTrackColor: const Color(0x66A8B6CD),
      secondary: Icon(icon, color: AppTheme.blue),
      title: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: onChanged == null ? const Color(0xFF7C879C) : AppTheme.blue,
          fontWeight: FontWeight.w700,
        ),
      ),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _DrawerActionButton extends StatelessWidget {
  const _DrawerActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          onTap();
        },
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          decoration: AppTheme.buildActionDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(14)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x331B305F),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: Colors.white),
              const SizedBox(width: 10),
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
