import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:scan_agbc/nucleo/tema/app_theme.dart';
import 'package:scan_agbc/nucleo/componentes/app_cards.dart';
import 'package:scan_agbc/nucleo/componentes/app_feedback_banner.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/package_tracking_result.dart';

class PackageTrackingResultCard extends StatelessWidget {
  const PackageTrackingResultCard({
    super.key,
    required this.result,
    this.showCodeHeader = true,
    this.showLocationArtwork = false,
    this.panelBackgroundColor = AppTheme.yellowSoft,
    this.showWeight = true,
    this.showAssignedCourier = true,
    this.extraCompactItems = const <Widget>[],
  });

  final PackageTrackingResult result;
  final bool showCodeHeader;
  final bool showLocationArtwork;
  final Color panelBackgroundColor;
  final bool showWeight;
  final bool showAssignedCourier;
  final List<Widget> extraCompactItems;

  @override
  Widget build(BuildContext context) {
    final compactItems = <_CompactInfoItemData>[
      _CompactInfoItemData(
        label: 'Ciudad',
        value: result.hasProvince
            ? '${result.safeCity} / ${result.safeProvince}'
            : result.safeCity,
        icon: Icons.location_city_rounded,
      ),
      _CompactInfoItemData(
        label: 'Teléfono',
        value: result.safePhone,
        icon: Icons.phone_rounded,
      ),
      if (showWeight)
        _CompactInfoItemData(
          label: 'Peso',
          value: result.safeWeight,
          icon: Icons.scale_rounded,
        ),
      _CompactInfoItemData(
        label: 'Contenido',
        value: result.safeDetail,
        icon: Icons.description_rounded,
      ),
    ];
    if (result.hasAssignmentStatus) {
      compactItems.addAll([
        _CompactInfoItemData(
          label: 'Estado',
          value: result.safeStateName,
          icon: Icons.assignment_turned_in_rounded,
        ),
        _CompactInfoItemData(
          label: 'Intentos',
          value: result.attemptCount.toString(),
          icon: Icons.replay_rounded,
          showWarningIcon: result.attemptCount >= 3,
        ),
      ]);
    }
    return AppPanelCard(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      backgroundColor: panelBackgroundColor,
      borderRadius: AppTheme.radiusLarge,
      borderColor: panelBackgroundColor == Colors.white
          ? AppTheme.lightBorder
          : AppTheme.softBorder,
      boxShadow: const [
        BoxShadow(
          color: Color(0x1F1B305F),
          blurRadius: 18,
          offset: Offset(0, 8),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showCodeHeader)
            _EmbeddedCodeHeader(
              code: result.code,
              feedbackMessage: 'Codigo copiado',
            ),
          if (showCodeHeader) const SizedBox(height: 16),
          AppPanelCard(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            backgroundColor: AppTheme.blue,
            borderRadius: const BorderRadius.all(Radius.circular(22)),
            borderColor: AppTheme.softBorder,
            boxShadow: const [],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.place_rounded,
                      color: AppTheme.yellowLight,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Zona o dirección',
                      style: TextStyle(
                        color: AppTheme.yellowLight,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (showLocationArtwork && !result.hasLocationNote)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Center(
                      child: Image.asset(
                        'assets/images/location_logo.png',
                        width: 132,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                if (result.hasLocationNote)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Center(
                      child: Column(
                        children: [
                          Image.asset(
                            'assets/images/address_not_found_warning.png',
                            width: 132,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'DIRECCION NO REGISTRADA',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              height: 1.05,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (result.hasHighlightLocation)
                  Align(
                    alignment: Alignment.center,
                    child: Text(
                      result.safeHighlightLocation,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppTheme.yellow,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _FullWidthInfoCard(
            label: 'Tipo de paquete',
            value: result.category.label,
            icon: Icons.inventory_2_rounded,
          ),
          const SizedBox(height: 12),
          _FullWidthInfoCard(
            label: 'Nombre',
            value: result.safeRecipientName,
            icon: Icons.person_rounded,
            copyValue: result.recipientName.trim().isEmpty
                ? null
                : result.recipientName.trim(),
          ),
          if (showAssignedCourier && result.hasAssignedCourier) ...[
            const SizedBox(height: 12),
            _AssignedCourierInfoCard(name: result.safeAssignedCourierName),
          ],
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 560;
              final cardWidth = isCompact
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  ...compactItems.map(
                    (item) => SizedBox(
                      width: cardWidth,
                      child: _CompactInfoCard(item: item),
                    ),
                  ),
                  ...extraCompactItems.map(
                    (item) => SizedBox(width: cardWidth, child: item),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

void scheduleMissingPackageLocationAlert({
  required BuildContext context,
  required PackageTrackingResult result,
}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    showAppFeedbackBanner(
      context,
      'Advertencia: este paquete no tiene zona ni dirección registrada.',
      tone: AppFeedbackTone.error,
      placement: AppFeedbackPlacement.top,
      topOffset: MediaQuery.of(context).viewPadding.top + kToolbarHeight + 20,
    );
  });
}

Future<void> _copyTextToClipboard(
  BuildContext context, {
  required String value,
  required String feedbackMessage,
}) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (!context.mounted) return;
  showAppFeedbackBanner(context, feedbackMessage, tone: AppFeedbackTone.info);
}

class PackageCodeSummaryCard extends StatelessWidget {
  const PackageCodeSummaryCard({
    super.key,
    required this.code,
    this.label = 'Codigo de paquete',
    this.icon = Icons.qr_code_2_rounded,
    this.feedbackMessage = 'Codigo copiado',
    this.statusMessage,
    this.statusColor,
  });

  final String code;
  final String label;
  final IconData icon;
  final String feedbackMessage;
  final String? statusMessage;
  final Color? statusColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: AppTheme.yellowSoft,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.softBorder),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppTheme.blue, size: 38),
          const SizedBox(height: 8),
          Text(
            label.toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.blue,
              fontWeight: FontWeight.w900,
              fontSize: 16,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Text(
                code,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.blueDark,
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                  letterSpacing: 0.5,
                ),
              ),
              _CopyIconButton(value: code, feedbackMessage: feedbackMessage),
            ],
          ),
          if (statusMessage != null && statusMessage!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              statusMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: statusColor ?? AppTheme.errorRed,
                fontWeight: FontWeight.w800,
                fontSize: 14,
                height: 1.2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmbeddedCodeHeader extends StatelessWidget {
  const _EmbeddedCodeHeader({
    required this.code,
    required this.feedbackMessage,
  });

  final String code;
  final String feedbackMessage;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          const Icon(Icons.qr_code_2_rounded, color: AppTheme.blue, size: 36),
          const SizedBox(height: 6),
          const Text(
            'CODIGO DE PAQUETE',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.blue,
              fontWeight: FontWeight.w900,
              fontSize: 16,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                code,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.blueDark,
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                  letterSpacing: 0.5,
                ),
              ),
              _CopyIconButton(value: code, feedbackMessage: feedbackMessage),
            ],
          ),
        ],
      ),
    );
  }
}

class _FullWidthInfoCard extends StatelessWidget {
  const _FullWidthInfoCard({
    required this.label,
    required this.value,
    required this.icon,
    this.copyValue,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? copyValue;

  @override
  Widget build(BuildContext context) {
    return AppSoftCard(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      backgroundColor: AppTheme.yellowField,
      borderRadius: const BorderRadius.all(Radius.circular(22)),
      borderColor: AppTheme.softBorder,
      child: Row(
        children: [
          Icon(icon, color: AppTheme.blue, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.blueDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        value,
                        style: const TextStyle(
                          color: AppTheme.blue,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                        ),
                      ),
                    ),
                    if (copyValue != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: _CopyIconButton(
                          value: copyValue!,
                          feedbackMessage: '$label copiado',
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactInfoCard extends StatelessWidget {
  const _CompactInfoCard({required this.item});

  final _CompactInfoItemData item;

  @override
  Widget build(BuildContext context) {
    return AppSoftCard(
      padding: const EdgeInsets.all(14),
      backgroundColor: AppTheme.yellowSurface,
      borderRadius: const BorderRadius.all(Radius.circular(18)),
      borderColor: AppTheme.lightBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(item.icon, color: AppTheme.blue, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.label.toUpperCase(),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppTheme.blueDark,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  item.value,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppTheme.blueDark,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
              ),
              if (item.showWarningIcon)
                const Icon(
                  Icons.warning_rounded,
                  color: AppTheme.errorRed,
                  size: 20,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompactInfoItemData {
  const _CompactInfoItemData({
    required this.label,
    required this.value,
    required this.icon,
    this.showWarningIcon = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool showWarningIcon;
}

class _AssignedCourierInfoCard extends StatelessWidget {
  const _AssignedCourierInfoCard({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = constraints.maxWidth >= 640;
        final content = isTablet
            ? ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _AssignedCourierIcon(isTablet: true),
                    const SizedBox(height: 6),
                    Text(
                      'ASIGNADO A',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppTheme.yellow,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      name.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppTheme.yellow,
                        fontWeight: FontWeight.w900,
                        height: 1.12,
                      ),
                    ),
                  ],
                ),
              )
            : Row(
                children: [
                  const _AssignedCourierIcon(isTablet: false),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ASIGNADO A',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: AppTheme.yellow,
                                letterSpacing: 0.4,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          name.toUpperCase(),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: AppTheme.yellow,
                                fontWeight: FontWeight.w900,
                                height: 1.12,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              );

        return DecoratedBox(
          decoration: AppTheme.buildActionDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(22)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isTablet ? 18 : 16,
              vertical: isTablet ? 12 : 10,
            ),
            child: SizedBox(
              width: double.infinity,
              child: isTablet ? Center(child: content) : content,
            ),
          ),
        );
      },
    );
  }
}

class _AssignedCourierIcon extends StatelessWidget {
  const _AssignedCourierIcon({required this.isTablet});

  final bool isTablet;

  @override
  Widget build(BuildContext context) {
    final size = isTablet ? 46.0 : 40.0;
    final iconSize = isTablet ? 24.0 : 21.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.yellow.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(
          color: AppTheme.yellow.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Icon(Icons.person_rounded, color: AppTheme.yellow, size: iconSize),
    );
  }
}

class _CopyIconButton extends StatelessWidget {
  const _CopyIconButton({required this.value, required this.feedbackMessage});

  final String value;
  final String feedbackMessage;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      radius: 20,
      onTap: () => _copyTextToClipboard(
        context,
        value: value,
        feedbackMessage: feedbackMessage,
      ),
      child: const Icon(Icons.copy_rounded, color: AppTheme.blue, size: 18),
    );
  }
}
