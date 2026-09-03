import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:scan_agbc/nucleo/componentes/app_feedback_banner.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/repositorios/package_tracking_repository.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/utilidades/package_code_classifier.dart';
import 'package:scan_agbc/funcionalidades/seguimiento/presentacion/paginas/package_tracking_search_page.dart';
import 'package:scan_agbc/funcionalidades/seguimiento/presentacion/paginas/siop_tracking_events_page.dart';
import 'package:scan_agbc/funcionalidades/seguimiento/presentacion/componentes/package_tracking_search_card.dart';
import 'package:scan_agbc/nucleo/tema/app_theme.dart';

class PackageTrackingPanel extends StatefulWidget {
  const PackageTrackingPanel({
    super.key,
    required this.repository,
    this.showPackageSearch = true,
    this.onOpenCourierLookup,
    this.courierLookupActionIcon = Icons.badge_rounded,
    this.courierLookupActionTitle = 'Asignar paquetes',
    this.courierLookupActionSubtitle =
        'Busca por nombre y revisa sus asignaciones activas.',
    this.onOpenRecentAssignments,
    this.onOpenSelfAssignment,
    this.onOpenContractPickup,
    this.onOpenScanner,
    this.scannerActionTitle = 'Registrar paquete',
    this.scannerActionSubtitle =
        'Abre el scanner para capturar ficha y registrar paquete.',
    this.onScanCodeWithCamera,
  });

  final PackageTrackingRepository repository;
  final bool showPackageSearch;
  final VoidCallback? onOpenCourierLookup;
  final IconData courierLookupActionIcon;
  final String courierLookupActionTitle;
  final String courierLookupActionSubtitle;
  final VoidCallback? onOpenRecentAssignments;
  final VoidCallback? onOpenSelfAssignment;
  final VoidCallback? onOpenContractPickup;
  final VoidCallback? onOpenScanner;
  final String scannerActionTitle;
  final String scannerActionSubtitle;
  final Future<String?> Function()? onScanCodeWithCamera;

  @override
  State<PackageTrackingPanel> createState() => _PackageTrackingPanelState();
}

class _PackageTrackingPanelState extends State<PackageTrackingPanel> {
  final TextEditingController _codeController = TextEditingController();
  final FocusNode _codeFocusNode = FocusNode();
  bool _processingCodeScan = false;
  bool _openingDetailPage = false;

  @override
  void dispose() {
    _codeController.dispose();
    _codeFocusNode.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_openingDetailPage) return;

    final validation = PackageCodeClassifier.validateForSearch(
      _codeController.text,
    );
    final code = validation.normalizedCode;
    if (!validation.isValid) {
      showAppFeedbackBanner(
        context,
        validation.errorMessage ?? 'Revisa el código e intenta nuevamente.',
        tone: AppFeedbackTone.error,
      );
      return;
    }

    FocusScope.of(context).unfocus();
    _openingDetailPage = true;
    try {
      final initialLookupFuture = widget.repository.findByCode(code);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PackageTrackingSearchPage(
            repository: widget.repository,
            initialCode: code,
            initialLookupFuture: initialLookupFuture,
          ),
        ),
      );
      _codeController.clear();
    } finally {
      _openingDetailPage = false;
    }
  }

  Future<void> _pasteCodeFromClipboard() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final rawCode = clipboardData?.text ?? '';
    final normalizedCode = PackageCodeClassifier.normalize(rawCode);
    if (normalizedCode.isEmpty) return;
    _codeController.value = TextEditingValue(
      text: normalizedCode,
      selection: TextSelection.collapsed(offset: normalizedCode.length),
    );
  }

  Future<void> _scanAndSearch(Future<String?> Function()? onResolveCode) async {
    if (onResolveCode == null || _processingCodeScan) return;

    setState(() {
      _processingCodeScan = true;
    });

    String? code;
    try {
      code = await onResolveCode();
    } finally {
      if (mounted) {
        setState(() {
          _processingCodeScan = false;
        });
      }
    }

    if (!mounted || code == null || code.isEmpty) return;

    _codeController.value = TextEditingValue(
      text: code,
      selection: TextSelection.collapsed(offset: code.length),
    );
    _search();
  }

  void _openTrackingEvents() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SiopTrackingEventsPage(
          repository: widget.repository,
          onScanCodeWithCamera: widget.onScanCodeWithCamera,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final content = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SearchCard(
                searchCard: widget.showPackageSearch
                    ? PackageTrackingSearchCard(
                        controller: _codeController,
                        focusNode: _codeFocusNode,
                        loading: _processingCodeScan,
                        buttonLabel: 'Consultar paquetes',
                        loadingLabel: 'Procesando...',
                        helperText:
                            'Consulta manualmente o toma una foto del código para buscarlo automáticamente.',
                        onSearch: _search,
                        onPasteCode: _pasteCodeFromClipboard,
                        onScanWithCamera: widget.onScanCodeWithCamera == null
                            ? null
                            : () => _scanAndSearch(widget.onScanCodeWithCamera),
                      )
                    : null,
                onOpenCourierLookup: widget.onOpenCourierLookup,
                courierLookupActionIcon: widget.courierLookupActionIcon,
                courierLookupActionTitle: widget.courierLookupActionTitle,
                courierLookupActionSubtitle: widget.courierLookupActionSubtitle,
                onOpenRecentAssignments: widget.onOpenRecentAssignments,
                onOpenSelfAssignment: widget.onOpenSelfAssignment,
                onOpenContractPickup: widget.onOpenContractPickup,
                onOpenScanner: widget.onOpenScanner,
                onOpenTrackingEvents: _openTrackingEvents,
                scannerActionTitle: widget.scannerActionTitle,
                scannerActionSubtitle: widget.scannerActionSubtitle,
              ),
            ],
          ),
        );

        return CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: content),
            ),
          ],
        );
      },
    );
  }
}

class _SearchCard extends StatelessWidget {
  const _SearchCard({
    required this.searchCard,
    required this.onOpenCourierLookup,
    required this.courierLookupActionIcon,
    required this.courierLookupActionTitle,
    required this.courierLookupActionSubtitle,
    required this.onOpenRecentAssignments,
    required this.onOpenSelfAssignment,
    required this.onOpenContractPickup,
    required this.onOpenScanner,
    required this.onOpenTrackingEvents,
    required this.scannerActionTitle,
    required this.scannerActionSubtitle,
  });

  final Widget? searchCard;
  final VoidCallback? onOpenCourierLookup;
  final IconData courierLookupActionIcon;
  final String courierLookupActionTitle;
  final String courierLookupActionSubtitle;
  final VoidCallback? onOpenRecentAssignments;
  final VoidCallback? onOpenSelfAssignment;
  final VoidCallback? onOpenContractPickup;
  final VoidCallback? onOpenScanner;
  final VoidCallback onOpenTrackingEvents;
  final String scannerActionTitle;
  final String scannerActionSubtitle;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    void addSection(Widget child, {double spacing = 16}) {
      if (children.isNotEmpty) {
        children.add(SizedBox(height: spacing));
      }
      children.add(child);
    }

    if (searchCard != null) {
      addSection(searchCard!, spacing: 0);
    }

    addSection(
      _QuickActionCard(
        icon: Icons.manage_search_rounded,
        title: 'Seguimiento SIOP',
        subtitle: 'Rastrea eventos oficiales por código.',
        onTap: onOpenTrackingEvents,
      ),
    );

    if (onOpenSelfAssignment != null) {
      addSection(
        _QuickActionCard(
          icon: Icons.add_task_rounded,
          title: 'Asignarse paquetes',
          subtitle:
              'Escanea o agrega varios códigos, revisa la prelista y asígnalos a tu cuenta.',
          onTap: onOpenSelfAssignment!,
        ),
      );
    }

    if (onOpenContractPickup != null) {
      addSection(
        _QuickActionCard(
          icon: Icons.inventory_2_rounded,
          title: 'Recoger paquetes',
          subtitle:
              'Escanea con la cámara o ingresa manualmente paquetes de contrato para confirmar su recojo.',
          onTap: onOpenContractPickup!,
        ),
      );
    }

    if (onOpenCourierLookup != null) {
      addSection(
        _QuickActionCard(
          icon: courierLookupActionIcon,
          title: courierLookupActionTitle,
          subtitle: courierLookupActionSubtitle,
          onTap: onOpenCourierLookup!,
        ),
      );
    }

    if (onOpenRecentAssignments != null) {
      addSection(
        _QuickActionCard(
          icon: Icons.history_rounded,
          title: 'Asignaciones recientes',
          subtitle: 'Revisa el historial regional y corrige asignaciones.',
          onTap: onOpenRecentAssignments!,
        ),
        spacing: 12,
      );
    }

    if (onOpenScanner != null) {
      addSection(
        _QuickActionCard(
          icon: Icons.inventory_2_rounded,
          title: scannerActionTitle,
          subtitle: scannerActionSubtitle,
          onTap: onOpenScanner!,
        ),
        spacing: 12,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(22)),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.buildActionDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(22)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x120F1E3D),
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              DecoratedBox(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.strongShadow,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppTheme.actionYellowStrong,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.strongBorder, width: 2),
                  ),
                  child: Icon(icon, color: AppTheme.blueDark, size: 26),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppTheme.yellowLight,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppTheme.yellow,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
