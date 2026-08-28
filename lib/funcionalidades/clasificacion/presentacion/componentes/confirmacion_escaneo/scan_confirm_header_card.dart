import 'package:flutter/material.dart';

import 'package:scan_agbc/nucleo/tema/app_theme.dart';

import 'scan_confirm_shared_widgets.dart';

class ScanConfirmHeaderCard extends StatelessWidget {
  const ScanConfirmHeaderCard({
    super.key,
    required this.tipoDocumento,
    required this.clasificacion,
  });

  final String tipoDocumento;
  final String clasificacion;

  @override
  Widget build(BuildContext context) {
    return ScanConfirmSectionCard(
      child: Row(
        children: [
          const CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.yellow,
            child: Icon(Icons.fact_check_outlined, color: AppTheme.blue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Revisa y corrige los datos',
                  style: TextStyle(
                    color: AppTheme.blue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tipo: $tipoDocumento',
                  style: TextStyle(
                    color: AppTheme.blue.withAlpha(230),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'CLASIFICACION: $clasificacion',
                  style: TextStyle(
                    color: AppTheme.blue.withAlpha(230),
                    fontWeight: FontWeight.w800,
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
