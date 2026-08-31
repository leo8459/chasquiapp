import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:scan_agbc/nucleo/componentes/app_cards.dart';
import 'package:scan_agbc/nucleo/componentes/app_feedback_banner.dart';
import 'package:scan_agbc/nucleo/componentes/app_page_scaffold.dart';
import 'package:scan_agbc/nucleo/tema/app_theme.dart';
import 'package:scan_agbc/nucleo/utilidades/user_friendly_error_mapper.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/tracking_events_result.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/repositorios/package_tracking_repository.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/utilidades/package_code_classifier.dart';
import 'package:scan_agbc/funcionalidades/seguimiento/presentacion/componentes/package_tracking_search_card.dart';

class SiopTrackingEventsPage extends StatefulWidget {
  const SiopTrackingEventsPage({
    super.key,
    required this.repository,
    this.onScanCodeWithCamera,
  });

  final PackageTrackingRepository repository;
  final Future<String?> Function()? onScanCodeWithCamera;

  @override
  State<SiopTrackingEventsPage> createState() => _SiopTrackingEventsPageState();
}

class _SiopTrackingEventsPageState extends State<SiopTrackingEventsPage> {
  final TextEditingController _codeController = TextEditingController();
  final FocusNode _codeFocusNode = FocusNode();
  bool _loading = false;
  bool _scanning = false;
  int _searchSequence = 0;
  TrackingEventsResult? _result;

  bool get _busy => _loading || _scanning;

  @override
  void dispose() {
    _codeController.dispose();
    _codeFocusNode.dispose();
    super.dispose();
  }

  Future<void> _pasteCodeFromClipboard() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final normalizedCode = PackageCodeClassifier.normalize(
      clipboardData?.text ?? '',
    );
    if (normalizedCode.isEmpty) return;
    _replaceVisibleCode(normalizedCode);
    setState(() {
      _result = null;
    });
  }

  Future<void> _scanAndSearch() async {
    final scan = widget.onScanCodeWithCamera;
    if (scan == null || _busy) return;

    setState(() {
      _scanning = true;
    });

    try {
      final code = await scan();
      if (!mounted || code == null || code.trim().isEmpty) return;

      await _search(rawCode: code);
    } finally {
      if (mounted) {
        setState(() {
          _scanning = false;
        });
      }
    }
  }

  Future<void> _search({String? rawCode}) async {
    if (_loading) return;

    final validation = PackageCodeClassifier.validateForSearch(
      rawCode ?? _codeController.text,
    );
    final normalizedCode = validation.normalizedCode;
    if (!validation.isValid) {
      showAppFeedbackBanner(
        context,
        validation.errorMessage ?? 'Revisa el código e intenta nuevamente.',
        tone: AppFeedbackTone.error,
      );
      return;
    }

    _replaceVisibleCode(normalizedCode);
    FocusScope.of(context).unfocus();
    final requestId = ++_searchSequence;
    setState(() {
      _loading = true;
      _result = null;
    });

    try {
      final result = await widget.repository.findTrackingEventsByCode(
        normalizedCode,
      );
      if (!mounted || requestId != _searchSequence) return;
      setState(() {
        _result = result;
      });
      if (!result.hasEvents) {
        showAppFeedbackBanner(
          context,
          'No encontramos eventos SIOP para $normalizedCode.',
          tone: AppFeedbackTone.info,
        );
      }
    } catch (error) {
      if (!mounted || requestId != _searchSequence) return;
      showAppFeedbackBanner(
        context,
        UserFriendlyErrorMapper.message(
          error,
          fallback: 'No pudimos consultar el seguimiento SIOP.',
        ),
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted && requestId == _searchSequence) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _replaceVisibleCode(String rawCode) {
    final normalizedCode = PackageCodeClassifier.normalize(rawCode);
    if (normalizedCode.isEmpty) return;

    _codeController.value = TextEditingValue(
      text: normalizedCode,
      selection: TextSelection.collapsed(offset: normalizedCode.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;

    return AppPageScaffold(
      resizeToAvoidBottomInset: false,
      title: 'Seguimiento SIOP',
      body: SingleChildScrollView(
        padding: AppTheme.pagePadding,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PackageTrackingSearchCard(
                  controller: _codeController,
                  focusNode: _codeFocusNode,
                  loading: _busy,
                  title: 'Rastreo del paquete',
                  hintText: 'Ejemplo: EN000000500BO',
                  buttonLabel: 'Consultar seguimiento',
                  loadingLabel: _scanning ? 'Escaneando...' : 'Consultando...',
                  helperText:
                      'Consulta eventos SIOP escribiendo el código o usando la cámara.',
                  onSearch: _search,
                  onPasteCode: _pasteCodeFromClipboard,
                  onScanWithCamera: widget.onScanCodeWithCamera == null
                      ? null
                      : _scanAndSearch,
                ),
                if (result != null) ...[
                  const SizedBox(height: 18),
                  _TrackingEventsResultCard(result: result),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackingEventsResultCard extends StatelessWidget {
  const _TrackingEventsResultCard({required this.result});

  final TrackingEventsResult result;

  @override
  Widget build(BuildContext context) {
    return AppPanelCard(
      padding: const EdgeInsets.all(12),
      backgroundColor: AppTheme.yellowSoft,
      borderRadius: AppTheme.radiusLarge,
      borderColor: AppTheme.softBorder,
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
          _TrackingResultHeader(result: result),
          const SizedBox(height: 12),
          if (!result.hasEvents)
            const _EmptyEventsCard()
          else
            DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0x66FFF8E8),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppTheme.lightBorder),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
                child: Column(
                  children: [
                    for (
                      var index = 0;
                      index < result.events.length;
                      index++
                    ) ...[
                      _TrackingEventTile(
                        event: result.events[index],
                        index: index,
                        isLast: index == result.events.length - 1,
                      ),
                      if (index != result.events.length - 1)
                        const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TrackingResultHeader extends StatelessWidget {
  const _TrackingResultHeader({required this.result});

  final TrackingEventsResult result;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        gradient: AppTheme.actionGradient,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.blueDark, width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2B1B305F),
            blurRadius: 14,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.yellow,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.yellowField, width: 1.4),
                ),
                child: const Icon(
                  Icons.timeline_rounded,
                  color: AppTheme.blueDark,
                  size: 25,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Seguimiento SIOP',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppTheme.yellowField,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Eventos encontrados para este paquete',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.yellowField.withValues(alpha: 0.86),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              _ResultCountPill(total: result.total),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TrackingInfoChip(
                icon: Icons.qr_code_2_rounded,
                label: result.safeCode,
              ),
              _TrackingInfoChip(
                icon: Icons.inventory_2_rounded,
                label: result.serviceLabel,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrackingInfoChip extends StatelessWidget {
  const _TrackingInfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.yellowField,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x99FFFFFF), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTheme.blueDark, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppTheme.blueDark,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackingEventTile extends StatelessWidget {
  const _TrackingEventTile({
    required this.event,
    required this.index,
    required this.isLast,
  });

  final TrackingEventSummary event;
  final int index;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final step = index + 1;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 34,
          child: Column(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.yellow,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.blueDark, width: 1.6),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x261B305F),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  '$step',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.blueDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 76,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.blue.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: _TrackingEventContent(event: event)),
      ],
    );
  }
}

class _TrackingEventContent extends StatelessWidget {
  const _TrackingEventContent({required this.event});

  final TrackingEventSummary event;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.yellowSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.lightBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x121B305F),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 6, color: AppTheme.blue),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            event.safeEvent,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: AppTheme.blueDark,
                                  fontWeight: FontWeight.w900,
                                  height: 1.18,
                                ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _ServicePill(label: event.safeService),
                      ],
                    ),
                    if (event.safeDetail.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text(
                        event.safeDetail,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.blueDark.withValues(alpha: 0.82),
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 7,
                      children: [
                        _EventMetaChip(
                          icon: Icons.schedule_rounded,
                          text: event.safeCreatedAt,
                        ),
                        _EventMetaChip(
                          icon: Icons.person_rounded,
                          text: event.safeUser,
                        ),
                        if (event.photo.trim().isNotEmpty)
                          const _EventMetaChip(
                            icon: Icons.photo_camera_rounded,
                            text: 'Foto registrada',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventMetaChip extends StatelessWidget {
  const _EventMetaChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.yellowField,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTheme.blue, size: 14),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppTheme.blueDark,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultCountPill extends StatelessWidget {
  const _ResultCountPill({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.yellow,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.yellowField, width: 1.1),
      ),
      child: Text(
        '$total',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: AppTheme.blueDark,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ServicePill extends StatelessWidget {
  const _ServicePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.blue,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppTheme.yellow,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _EmptyEventsCard extends StatelessWidget {
  const _EmptyEventsCard();

  @override
  Widget build(BuildContext context) {
    return AppSoftCard(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      backgroundColor: AppTheme.yellowField,
      borderRadius: const BorderRadius.all(Radius.circular(18)),
      borderColor: AppTheme.lightBorder,
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: AppTheme.blue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No hay eventos registrados para este código.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.blueDark,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
