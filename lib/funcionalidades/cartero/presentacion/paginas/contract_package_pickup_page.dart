import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/repositorios/package_tracking_repository.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/utilidades/package_code_classifier.dart';
import 'package:scan_agbc/funcionalidades/seguimiento/presentacion/componentes/package_tracking_search_card.dart';
import 'package:scan_agbc/nucleo/componentes/app_cards.dart';
import 'package:scan_agbc/nucleo/componentes/app_feedback_banner.dart';
import 'package:scan_agbc/nucleo/componentes/app_page_scaffold.dart';
import 'package:scan_agbc/nucleo/tema/app_theme.dart';
import 'package:scan_agbc/nucleo/utilidades/user_friendly_error_mapper.dart';

class ContractPackagePickupPage extends StatefulWidget {
  const ContractPackagePickupPage({
    super.key,
    required this.repository,
    this.onScanCodeWithCamera,
  });

  final PackageTrackingRepository repository;
  final Future<String?> Function()? onScanCodeWithCamera;

  @override
  State<ContractPackagePickupPage> createState() =>
      _ContractPackagePickupPageState();
}

class _ContractPackagePickupPageState extends State<ContractPackagePickupPage> {
  final TextEditingController _codeController = TextEditingController();
  final FocusNode _codeFocusNode = FocusNode();
  final Set<String> _selectedCodes = <String>{};
  bool _scanning = false;
  bool _submitting = false;

  bool get _busy => _scanning || _submitting;

  @override
  void dispose() {
    _codeController.dispose();
    _codeFocusNode.dispose();
    super.dispose();
  }

  Future<void> _addCode(String rawCode) async {
    final validation = PackageCodeClassifier.validateForSearch(rawCode);
    if (!validation.isValid) {
      showAppFeedbackBanner(
        context,
        validation.errorMessage ?? 'Ingresa un código de paquete válido.',
        tone: AppFeedbackTone.error,
      );
      return;
    }

    setState(() {
      _selectedCodes.add(validation.normalizedCode);
      _codeController.clear();
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _pasteCode() async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final code = clipboard?.text ?? '';
    if (code.trim().isNotEmpty) await _addCode(code);
  }

  Future<void> _scanCode() async {
    final scan = widget.onScanCodeWithCamera;
    if (scan == null || _busy) return;
    setState(() => _scanning = true);
    try {
      final code = await scan();
      if (mounted && code != null && code.trim().isNotEmpty) {
        await _addCode(code);
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _pickupSelected() async {
    if (_selectedCodes.isEmpty || _submitting) return;
    final count = _selectedCodes.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar recojo'),
        content: Text(
          'Se marcarán $count paquete(s) de contrato como recogidos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Recoger'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      final result = await widget.repository.pickupContractPackages(
        _selectedCodes.toList(growable: false),
      );
      if (!mounted) return;
      setState(() {
        _selectedCodes
          ..clear()
          ..addAll(result.unprocessedCodes);
      });
      final partial = result.unprocessedCodes.isNotEmpty;
      showAppFeedbackBanner(
        context,
        partial
            ? '${result.pickedUpCount} paquete(s) recogido(s). ${result.unprocessedCodes.length} no se procesaron y permanecen en la prelista.'
            : (result.message.isEmpty
                  ? '${result.pickedUpCount} paquete(s) recogido(s) correctamente.'
                  : result.message),
        tone: partial ? AppFeedbackTone.info : AppFeedbackTone.success,
      );
    } catch (error) {
      if (!mounted) return;
      showAppFeedbackBanner(
        context,
        UserFriendlyErrorMapper.message(
          error,
          fallback: 'No pudimos recoger los paquetes seleccionados.',
        ),
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final codes = _selectedCodes.toList()..sort();
    return AppPageScaffold(
      title: 'Recoger paquetes',
      resizeToAvoidBottomInset: true,
      body: ListView(
        padding: AppTheme.pagePadding,
        children: [
          PackageTrackingSearchCard(
            controller: _codeController,
            focusNode: _codeFocusNode,
            loading: _busy,
            title: 'Agregar paquete de contrato',
            hintText: 'Escribe o escanea el código',
            buttonLabel: 'Agregar a prelista',
            loadingLabel: _scanning ? 'Escaneando...' : 'Procesando...',
            helperText:
                'Agrega los códigos manualmente o usa la cámara antes de confirmar el recojo.',
            onSearch: () => _addCode(_codeController.text),
            onPasteCode: _pasteCode,
            onScanWithCamera: widget.onScanCodeWithCamera == null
                ? null
                : _scanCode,
          ),
          const SizedBox(height: 16),
          AppPanelCard(
            padding: const EdgeInsets.all(16),
            backgroundColor: AppTheme.yellowSoft,
            borderColor: AppTheme.softBorder,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.inventory_rounded, color: AppTheme.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Prelista (${codes.length})',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: AppTheme.blueDark,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                    if (codes.isNotEmpty)
                      TextButton(
                        onPressed: _submitting
                            ? null
                            : () => setState(_selectedCodes.clear),
                        child: const Text('Limpiar'),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (codes.isEmpty)
                  const Text('Todavía no agregaste paquetes.')
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: codes
                        .map(
                          (code) => InputChip(
                            label: Text(code),
                            onDeleted: _submitting
                                ? null
                                : () => setState(
                                    () => _selectedCodes.remove(code),
                                  ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                if (codes.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _submitting ? null : _pickupSelected,
                    icon: _submitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.inventory_2_rounded),
                    label: Text(
                      _submitting
                          ? 'Recogiendo...'
                          : 'Recoger ${codes.length} paquete(s)',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
