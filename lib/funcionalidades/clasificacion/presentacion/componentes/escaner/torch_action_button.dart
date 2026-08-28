import 'package:flutter/material.dart';

import 'package:scan_agbc/funcionalidades/clasificacion/presentacion/controladores/scanner_controller.dart';

class TorchActionButton extends StatelessWidget {
  const TorchActionButton({super.key, required this.controller});

  final ScannerController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller.cameraListenable,
      builder: (context, _) {
        return IconButton(
          tooltip: controller.torchEnabled
              ? 'Apagar linterna'
              : 'Encender linterna',
          onPressed: controller.cameraReady ? controller.toggleTorch : null,
          icon: Icon(
            controller.torchEnabled
                ? Icons.flashlight_on_rounded
                : Icons.flashlight_off_rounded,
          ),
        );
      },
    );
  }
}
