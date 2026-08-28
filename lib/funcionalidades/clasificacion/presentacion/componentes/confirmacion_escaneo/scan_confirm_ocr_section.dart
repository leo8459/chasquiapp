import 'package:flutter/material.dart';

import 'package:scan_agbc/nucleo/tema/app_theme.dart';

import 'scan_confirm_shared_widgets.dart';

class ScanConfirmOcrSection extends StatelessWidget {
  const ScanConfirmOcrSection({super.key, required this.ocrRaw});

  final String ocrRaw;

  @override
  Widget build(BuildContext context) {
    return ScanConfirmSectionCard(
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text(
          'Ver OCR completo',
          style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.blue),
        ),
        iconColor: AppTheme.blue,
        collapsedIconColor: AppTheme.blue,
        shape: const Border(),
        collapsedShape: const Border(),
        children: [
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.yellowField,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.blue),
            ),
            child: SelectableText(
              ocrRaw,
              style: const TextStyle(color: AppTheme.blue, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
