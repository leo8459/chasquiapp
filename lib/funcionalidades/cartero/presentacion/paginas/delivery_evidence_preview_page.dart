import 'package:flutter/material.dart';

import 'package:scan_agbc/nucleo/componentes/app_cards.dart';
import 'package:scan_agbc/nucleo/componentes/app_page_scaffold.dart';
import 'package:scan_agbc/nucleo/tema/app_theme.dart';
import 'package:scan_agbc/funcionalidades/cartero/presentacion/paginas/delivery_photo_capture_page.dart';

enum DeliveryEvidencePreviewDecision { keep, replace }

class DeliveryEvidencePreviewPage extends StatelessWidget {
  const DeliveryEvidencePreviewPage({
    super.key,
    required this.photo,
    required this.title,
    required this.headline,
    required this.supportingText,
    required this.replaceActionLabel,
    this.headerIcon = Icons.image_rounded,
  });

  final DeliveryPhotoCaptureResult photo;
  final String title;
  final String headline;
  final String supportingText;
  final String replaceActionLabel;
  final IconData headerIcon;

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: title,
      backgroundDecoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.yellowLight,
            AppTheme.yellowField,
            AppTheme.orangeWarm,
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSoftCard(
              padding: const EdgeInsets.all(14),
              backgroundColor: AppTheme.yellowSurface,
              borderRadius: AppTheme.radiusLarge,
              borderColor: AppTheme.lightBorder,
              boxShadow: const [
                BoxShadow(
                  color: AppTheme.softShadow,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.actionYellowStrong,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(headerIcon, color: AppTheme.blueDark, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          headline,
                          style: const TextStyle(
                            color: AppTheme.blueDark,
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          supportingText,
                          style: const TextStyle(
                            color: AppTheme.blueDark,
                            fontWeight: FontWeight.w600,
                            height: 1.28,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.blueDark,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: AppTheme.actionYellowStrong,
                    width: 2,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: AppTheme.strongShadow,
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: InteractiveViewer(
                    minScale: 0.9,
                    maxScale: 4,
                    child: SizedBox.expand(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: Image.memory(
                          photo.bytes,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            AppActionTray(
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(DeliveryEvidencePreviewDecision.replace),
                      icon: const Icon(Icons.replay_rounded),
                      label: Text(replaceActionLabel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(DeliveryEvidencePreviewDecision.keep),
                      icon: const Icon(Icons.check_circle_rounded),
                      label: const Text('Volver'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
