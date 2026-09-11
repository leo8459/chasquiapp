import 'package:flutter/material.dart';

import 'package:scan_agbc/nucleo/tema/app_theme.dart';

Future<void> showAppSuccessDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      icon: const CircleAvatar(
        radius: 28,
        backgroundColor: Color(0xFFE5F7EC),
        child: Icon(
          Icons.check_circle_rounded,
          color: AppTheme.successGreen,
          size: 38,
        ),
      ),
      title: Text(title, textAlign: TextAlign.center),
      content: Text(message, textAlign: TextAlign.center),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton.icon(
          onPressed: () => Navigator.of(dialogContext).pop(),
          icon: const Icon(Icons.done_rounded),
          label: const Text('Aceptar'),
        ),
      ],
    ),
  );
}
