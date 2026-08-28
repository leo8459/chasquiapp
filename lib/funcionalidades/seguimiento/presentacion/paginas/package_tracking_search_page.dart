import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import 'package:scan_agbc/nucleo/tema/app_theme.dart';
import 'package:scan_agbc/nucleo/utilidades/user_friendly_error_mapper.dart';
import 'package:scan_agbc/nucleo/componentes/app_cards.dart';
import 'package:scan_agbc/nucleo/componentes/app_feedback_banner.dart';
import 'package:scan_agbc/nucleo/componentes/app_page_scaffold.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/package_tracking_result.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/repositorios/package_tracking_repository.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/utilidades/package_code_classifier.dart';
import 'package:scan_agbc/funcionalidades/seguimiento/presentacion/componentes/package_tracking_search_card.dart';
import 'package:scan_agbc/funcionalidades/seguimiento/presentacion/componentes/package_tracking_result_card.dart';

class PackageTrackingSearchPage extends StatefulWidget {
  const PackageTrackingSearchPage({
    super.key,
    this.initialCode,
    required this.repository,
    this.assignmentTargetName,
    this.onAssignPackage,
    this.initialLookupFuture,
  });

  final String? initialCode;
  final PackageTrackingRepository repository;
  final String? assignmentTargetName;
  final Future<void> Function()? onAssignPackage;
  final Future<PackageTrackingResult?>? initialLookupFuture;

  @override
  State<PackageTrackingSearchPage> createState() =>
      _PackageTrackingSearchPageState();
}

class _PackageTrackingSearchPageState extends State<PackageTrackingSearchPage> {
  late final TextEditingController _codeController;
  final FocusNode _codeFocusNode = FocusNode();

  bool _loading = false;
  bool _assigningPackage = false;
  PackageTrackingResult? _result;
  String? _notFoundCode;
  bool _missingLocationAlertShown = false;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(text: widget.initialCode);

    if (widget.initialCode != null && widget.initialCode!.isNotEmpty) {
      _loading = true;
      unawaited(_loadInitialResult());
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _codeFocusNode.dispose();
    super.dispose();
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

  Future<void> _loadInitialResult() async {
    final validation = PackageCodeClassifier.validateForSearch(
      widget.initialCode ?? '',
    );
    final normalizedCode = validation.normalizedCode;
    if (!validation.isValid) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _result = null;
        _notFoundCode = null;
      });
      return;
    }

    try {
      final future = widget.initialLookupFuture;
      final result = future ?? widget.repository.findByCode(normalizedCode);
      final resolved = await result;
      if (!mounted) return;
      setState(() {
        _result = resolved;
        _notFoundCode = resolved == null ? normalizedCode : null;
      });
      if (resolved == null) {
        _showDeferredBanner(
          'No se localizo un registro para $normalizedCode.',
          tone: AppFeedbackTone.error,
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _result = null;
        _notFoundCode = null;
      });
      _showDeferredBanner(_mapError(error), tone: AppFeedbackTone.error);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _showDeferredBanner(String message, {required AppFeedbackTone tone}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showAppFeedbackBanner(context, message, tone: tone);
    });
  }

  Future<void> _search() async {
    if (_loading) return;

    final validation = PackageCodeClassifier.validateForSearch(
      _codeController.text,
    );
    final normalizedCode = validation.normalizedCode;
    if (!validation.isValid) {
      setState(() {
        _result = null;
        _notFoundCode = null;
      });
      showAppFeedbackBanner(
        context,
        validation.errorMessage ?? 'Revisa el código e intenta nuevamente.',
        tone: AppFeedbackTone.error,
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _result = null;
      _notFoundCode = null;
      _missingLocationAlertShown = false;
    });

    try {
      final result = await widget.repository.findByCode(normalizedCode);
      if (!mounted) return;
      setState(() {
        _result = result;
        _notFoundCode = result == null ? normalizedCode : null;
      });
      if (result == null) {
        showAppFeedbackBanner(
          context,
          'No se localizo un registro para $normalizedCode.',
          tone: AppFeedbackTone.error,
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _result = null;
        _notFoundCode = null;
      });
      showAppFeedbackBanner(
        context,
        _mapError(error),
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _mapError(Object error) {
    return UserFriendlyErrorMapper.message(
      error,
      fallback: 'No pudimos consultar este paquete. Intenta nuevamente.',
    );
  }

  String _mapAssignmentError(Object error) {
    return UserFriendlyErrorMapper.message(
      error,
      fallback:
          'No pudimos completar la asignación en este momento. Intenta nuevamente.',
    );
  }

  Future<void> _assignPackageFromDetail() async {
    final assignPackage = widget.onAssignPackage;
    if (assignPackage == null || _assigningPackage) return;

    final shouldAssign = await _showAssignPackageDialog();
    if (shouldAssign != true || !mounted) return;

    setState(() {
      _assigningPackage = true;
    });

    try {
      await assignPackage();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      showAppFeedbackBanner(
        context,
        _mapAssignmentError(error),
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _assigningPackage = false;
        });
      }
    }
  }

  Future<bool?> _showAssignPackageDialog() {
    final packageCode = _result?.code ?? widget.initialCode ?? 'este paquete';
    final targetName = widget.assignmentTargetName?.trim().toUpperCase();
    final targetLabel = targetName == null || targetName.isEmpty
        ? 'este cartero'
        : targetName;

    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Asignar paquete'),
          content: Text('Se asignara $packageCode a $targetLabel.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Asignar'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildResultCard(PackageTrackingResult result) {
    final assignmentTargetName = widget.assignmentTargetName?.trim();
    return PackageTrackingResultCard(
      result: result,
      showCodeHeader: true,
      showLocationArtwork: true,
      panelBackgroundColor: Colors.white,
      extraCompactItems:
          assignmentTargetName == null || assignmentTargetName.isEmpty
          ? const <Widget>[]
          : <Widget>[_AssignmentTargetInfoCard(name: assignmentTargetName)],
    );
  }

  Widget _buildResultCardWithActions(PackageTrackingResult result) {
    final assignPackage = widget.onAssignPackage;
    if (assignPackage == null) {
      return _buildResultCard(result);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildResultCard(result),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _assigningPackage ? null : _assignPackageFromDetail,
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.blue,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppTheme.blue.withValues(alpha: 0.65),
            disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
            minimumSize: const Size.fromHeight(54),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: AppTheme.radiusMedium),
          ),
          icon: _assigningPackage
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.assignment_ind_rounded),
          label: Text(_assigningPackage ? 'Asignando...' : 'Asignar paquete'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final readOnlyCodeView =
        widget.initialCode != null && widget.initialCode!.trim().isNotEmpty;
    final result = _result;
    final notFoundCode = _notFoundCode;
    const notFoundMessage =
        'No se localizo el paquete en los registros disponibles.';

    if (result != null &&
        result.hasLocationNote &&
        !result.hasHighlightLocation &&
        !_missingLocationAlertShown) {
      _missingLocationAlertShown = true;
      scheduleMissingPackageLocationAlert(context: context, result: result);
    }

    return AppPageScaffold(
      resizeToAvoidBottomInset: false,
      title: 'Detalle Paquete',
      body: LayoutBuilder(
        builder: (context, constraints) {
          final showWideResult = constraints.maxWidth >= 920 && result != null;

          final lookupColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!readOnlyCodeView)
                PackageTrackingSearchCard(
                  controller: _codeController,
                  focusNode: _codeFocusNode,
                  loading: _loading,
                  buttonLabel: 'Consultar paquetes',
                  onSearch: _search,
                  onPasteCode: _pasteCodeFromClipboard,
                ),
              if (result != null && !readOnlyCodeView) ...[
                const SizedBox(height: 20),
                PackageTrackingResultCard(
                  result: result,
                  showCodeHeader: true,
                  showLocationArtwork: true,
                  panelBackgroundColor: Colors.white,
                ),
              ],
              if (result == null &&
                  notFoundCode != null &&
                  !readOnlyCodeView) ...[
                const SizedBox(height: 20),
                PackageCodeSummaryCard(
                  code: notFoundCode,
                  statusMessage: notFoundMessage,
                  statusColor: AppTheme.errorRed,
                ),
              ],
            ],
          );

          if (readOnlyCodeView && result != null) {
            return SingleChildScrollView(
              padding: AppTheme.pagePadding,
              child: _buildResultCardWithActions(result),
            );
          }

          if (readOnlyCodeView && result == null && notFoundCode == null) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.blue),
            );
          }

          if (readOnlyCodeView && result == null && notFoundCode != null) {
            return SingleChildScrollView(
              padding: AppTheme.pagePadding,
              child: PackageCodeSummaryCard(
                code: notFoundCode,
                statusMessage: notFoundMessage,
                statusColor: AppTheme.errorRed,
              ),
            );
          }

          if (showWideResult) {
            return SingleChildScrollView(
              padding: AppTheme.pagePadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 4, child: lookupColumn),
                      const SizedBox(width: 20),
                      Expanded(
                        flex: 6,
                        child: _buildResultCardWithActions(result),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            padding: AppTheme.pagePadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [lookupColumn],
            ),
          );
        },
      ),
    );
  }
}

class _AssignmentTargetInfoCard extends StatelessWidget {
  const _AssignmentTargetInfoCard({required this.name});

  final String name;

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
              const Icon(
                Icons.assignment_ind_rounded,
                color: AppTheme.blue,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ASIGNAR A',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppTheme.blueDark,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            name.toUpperCase(),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppTheme.blueDark,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
