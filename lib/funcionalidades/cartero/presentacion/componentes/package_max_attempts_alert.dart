import 'package:flutter/material.dart';

import 'package:scan_agbc/nucleo/tema/app_theme.dart';

Future<void> showPackageMaxAttemptsAlert(BuildContext context) async {
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppTheme.radiusLarge),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/address_not_found_warning.png',
              width: 86,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 16),
            const Text(
              'INTENTOS MAXIMOS REALIZADOS',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.blueDark,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: AppTheme.radiusMedium,
              ),
            ),
            child: const Text('Continuar'),
          ),
        ],
      );
    },
  );
}
