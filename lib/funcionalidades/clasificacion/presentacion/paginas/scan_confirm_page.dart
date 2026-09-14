import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'package:scan_agbc/nucleo/componentes/app_feedback_banner.dart';
import 'package:scan_agbc/nucleo/utilidades/user_friendly_error_mapper.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/dominio/modelos/scan_result.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/dominio/modelos/scanned_ficha_data.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/dominio/modelos/ventanilla_option.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/dominio/repositorios/scanner_repository.dart';
import 'package:scan_agbc/nucleo/tema/app_theme.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/utilidades/app_strings.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/utilidades/scan_confirm_validator.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/presentacion/componentes/confirmacion_escaneo/scan_confirm_fields_section.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/presentacion/componentes/confirmacion_escaneo/scan_confirm_header_card.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/presentacion/componentes/confirmacion_escaneo/scan_confirm_keyboard_overlay.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/presentacion/componentes/confirmacion_escaneo/scan_confirm_ocr_section.dart';

enum _TargetField { barcode, nombre, telefono, peso, ventanilla }

class ScanConfirmPage extends StatefulWidget {
  const ScanConfirmPage({
    super.key,
    required this.data,
    required this.scanRepository,
    this.onSaved,
  });

  final ScannedFichaData data;
  final ScanRepository scanRepository;
  final ValueChanged<ScanResult>? onSaved;

  @override
  State<ScanConfirmPage> createState() => _ScanConfirmPageState();
}

class _ScanConfirmPageState extends State<ScanConfirmPage>
    with WidgetsBindingObserver {
  static const int _maxVisibleSuggestionTokens = 300;
  static const Duration _saveTimeout = Duration(seconds: 25);
  static const Object _unset = Object();

  late final TextEditingController _barcodeController;
  late final TextEditingController _nombreController;
  late final TextEditingController _telefonoController;
  late final TextEditingController _pesoController;

  late final FocusNode _barcodeFocusNode;
  late final FocusNode _nombreFocusNode;
  late final FocusNode _telefonoFocusNode;
  late final FocusNode _pesoFocusNode;

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _barcodeFieldKey = GlobalKey();
  final GlobalKey _nombreFieldKey = GlobalKey();
  final GlobalKey _telefonoFieldKey = GlobalKey();
  final GlobalKey _pesoFieldKey = GlobalKey();
  final GlobalKey _ventanillaFieldKey = GlobalKey();

  late final ValueNotifier<_ScanConfirmHeaderState> _headerState;
  late final ValueNotifier<_ScanConfirmFieldsState> _fieldsState;
  late final ValueNotifier<_ScanConfirmOverlayState> _overlayState;
  late final ValueNotifier<String> _tipoDocumentoNotifier;

  double _lastKeyboardInset = 0;
  int _focusScrollRequestId = 0;

  static const List<String> _departamentos = [
    'LA PAZ',
    'COCHABAMBA',
    'SANTA CRUZ',
    'ORURO',
    'POTOSI',
    'CHUQUISACA',
    'TARIJA',
    'BENI',
    'PANDO',
  ];

  static const List<String> _tipoDocumentoOpciones = ['PP', 'PG', 'SOBRE'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _barcodeController = TextEditingController(
      text: widget.data.barcode.toUpperCase(),
    );
    _nombreController = TextEditingController(
      text: widget.data.nombre.toUpperCase(),
    );
    _telefonoController = TextEditingController(text: widget.data.telefono);
    _pesoController = TextEditingController();

    _barcodeFocusNode = FocusNode();
    _nombreFocusNode = FocusNode();
    _telefonoFocusNode = FocusNode();
    _pesoFocusNode = FocusNode();

    _headerState = ValueNotifier<_ScanConfirmHeaderState>(
      _ScanConfirmHeaderState(
        clasificacion: _clasificacionFromBarcode(_barcodeController.text),
        selectedTipoDocumento: 'PP',
      ),
    );
    _tipoDocumentoNotifier = ValueNotifier<String>('PP');
    _fieldsState = ValueNotifier<_ScanConfirmFieldsState>(
      _ScanConfirmFieldsState(
        selectedCiudad: 'LA PAZ',
        isAduana: false,
        loadingVentanillas: true,
        ventanillas: const [],
        selectedVentanillaId: null,
        showValidationErrors: false,
      ),
    );
    _overlayState = ValueNotifier<_ScanConfirmOverlayState>(
      _ScanConfirmOverlayState(
        confirming: false,
        saveDialogVisible: false,
        showSuggestions: false,
        keyboardUiVisible: false,
        ocrTokens: List<String>.unmodifiable(widget.data.ocrTokens),
        activeField: _TargetField.nombre,
      ),
    );

    _barcodeFocusNode.addListener(_handleFocusChange);
    _nombreFocusNode.addListener(_handleFocusChange);
    _telefonoFocusNode.addListener(_handleFocusChange);
    _pesoFocusNode.addListener(_handleFocusChange);
    _barcodeController.addListener(_handleBarcodeChange);

    _loadVentanillas();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _barcodeFocusNode.removeListener(_handleFocusChange);
    _nombreFocusNode.removeListener(_handleFocusChange);
    _telefonoFocusNode.removeListener(_handleFocusChange);
    _pesoFocusNode.removeListener(_handleFocusChange);
    _barcodeController.removeListener(_handleBarcodeChange);

    _barcodeController.dispose();
    _nombreController.dispose();
    _telefonoController.dispose();
    _pesoController.dispose();

    _barcodeFocusNode.dispose();
    _nombreFocusNode.dispose();
    _telefonoFocusNode.dispose();
    _pesoFocusNode.dispose();

    _headerState.dispose();
    _tipoDocumentoNotifier.dispose();
    _fieldsState.dispose();
    _overlayState.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return;

    final currentInset = views.first.viewInsets.bottom;
    final keyboardIsHiding = currentInset < _lastKeyboardInset;
    final keyboardIsOpening = currentInset > _lastKeyboardInset;
    final keyboardClosed = currentInset == 0;
    final hasFocusedInput = _hasAnyInputFocus();

    if (keyboardClosed) {
      _updateOverlayState((state) {
        if (!state.keyboardUiVisible && !state.showSuggestions) return state;
        return state.copyWith(keyboardUiVisible: false, showSuggestions: false);
      });
    } else if (keyboardIsHiding) {
      _updateOverlayState((state) {
        if (!state.showSuggestions) return state;
        return state.copyWith(showSuggestions: false);
      });
    } else if (keyboardIsOpening && hasFocusedInput) {
      _updateOverlayState((state) {
        if (state.keyboardUiVisible) return state;
        return state.copyWith(keyboardUiVisible: true);
      });
      _scheduleEnsureFieldVisible(_currentTargetField(), immediate: true);
    }

    _lastKeyboardInset = currentInset;
  }

  bool _hasAnyInputFocus() {
    return _barcodeFocusNode.hasFocus ||
        _nombreFocusNode.hasFocus ||
        _telefonoFocusNode.hasFocus ||
        _pesoFocusNode.hasFocus;
  }

  Future<void> _loadVentanillas() async {
    _updateFieldsState((state) => state.copyWith(loadingVentanillas: true));
    try {
      final options = await widget.scanRepository.getVentanillas();
      if (!mounted) return;
      _updateFieldsState((state) {
        final currentSelected = state.selectedVentanillaId;
        final hasCurrent =
            currentSelected != null &&
            options.any((option) => option.id == currentSelected);
        return state.copyWith(
          loadingVentanillas: false,
          ventanillas: List<VentanillaOption>.unmodifiable(options),
          selectedVentanillaId: hasCurrent ? currentSelected : null,
        );
      });
    } catch (_) {
      if (!mounted) return;
      _updateFieldsState(
        (state) => state.copyWith(
          loadingVentanillas: false,
          ventanillas: const [],
          selectedVentanillaId: null,
        ),
      );
    }
  }

  void _updateHeaderState(
    _ScanConfirmHeaderState Function(_ScanConfirmHeaderState current) updater,
  ) {
    final current = _headerState.value;
    final next = updater(current);
    if (next == current) return;
    _headerState.value = next;
    if (_tipoDocumentoNotifier.value != next.selectedTipoDocumento) {
      _tipoDocumentoNotifier.value = next.selectedTipoDocumento;
    }
  }

  void _updateFieldsState(
    _ScanConfirmFieldsState Function(_ScanConfirmFieldsState current) updater,
  ) {
    final current = _fieldsState.value;
    final next = updater(current);
    if (next == current) return;
    _fieldsState.value = next;
  }

  void _updateOverlayState(
    _ScanConfirmOverlayState Function(_ScanConfirmOverlayState current) updater,
  ) {
    final current = _overlayState.value;
    final next = updater(current);
    if (next == current) return;
    _overlayState.value = next;
  }

  String _clasificacionFromBarcode(String barcode) {
    final trimmed = barcode.trim();
    if (trimmed.isEmpty) return 'SIN CLASIFICAR';

    final prefix = trimmed[0].toUpperCase();
    if (prefix == 'R') return 'PAQUETE CERTIFICADO';
    if (prefix == 'U' || prefix == 'L') return 'PAQUETE ORDINARIO';
    return 'SIN CLASIFICAR';
  }

  void _handleBarcodeChange() {
    final nextClasificacion = _clasificacionFromBarcode(
      _barcodeController.text,
    );
    _updateHeaderState((state) {
      if (state.clasificacion == nextClasificacion) return state;
      return state.copyWith(clasificacion: nextClasificacion);
    });
  }

  void _handleFocusChange() {
    final keyboardVisible =
        _barcodeFocusNode.hasFocus ||
        _nombreFocusNode.hasFocus ||
        _telefonoFocusNode.hasFocus ||
        _pesoFocusNode.hasFocus;

    final activeField = _currentTargetField();

    _updateOverlayState((state) {
      final shouldHideSuggestions = !keyboardVisible;
      return state.copyWith(
        keyboardUiVisible: keyboardVisible,
        showSuggestions: shouldHideSuggestions ? false : state.showSuggestions,
        activeField: activeField,
      );
    });

    if (keyboardVisible) {
      _scheduleEnsureFieldVisible(activeField);
    }
  }

  void _scheduleEnsureFieldVisible(
    _TargetField field, {
    bool immediate = false,
  }) {
    _focusScrollRequestId++;
    final requestId = _focusScrollRequestId;

    void runIfCurrent() {
      if (!mounted || requestId != _focusScrollRequestId) return;
      if (field != _TargetField.ventanilla && _currentTargetField() != field) {
        return;
      }
      _ensureFieldVisible(field);
    }

    if (immediate) {
      WidgetsBinding.instance.addPostFrameCallback((_) => runIfCurrent());
      Future<void>.delayed(const Duration(milliseconds: 28), runIfCurrent);
      return;
    }

    Future<void>.delayed(const Duration(milliseconds: 28), runIfCurrent);
  }

  void _ensureFieldVisible(_TargetField field) {
    final context = switch (field) {
      _TargetField.barcode => _barcodeFieldKey.currentContext,
      _TargetField.nombre => _nombreFieldKey.currentContext,
      _TargetField.telefono => _telefonoFieldKey.currentContext,
      _TargetField.peso => _pesoFieldKey.currentContext,
      _TargetField.ventanilla => _ventanillaFieldKey.currentContext,
    };
    if (!mounted || context == null) return;
    if (!_scrollController.hasClients) return;

    final renderObject = context.findRenderObject();
    if (renderObject == null) return;
    final viewport = RenderAbstractViewport.of(renderObject);

    final reveal = viewport.getOffsetToReveal(renderObject, 0.35);
    final position = _scrollController.position;
    final target = reveal.offset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    _scrollController.jumpTo(target);
  }

  _TargetField _currentTargetField() {
    if (_barcodeFocusNode.hasFocus) return _TargetField.barcode;
    if (_telefonoFocusNode.hasFocus) return _TargetField.telefono;
    if (_pesoFocusNode.hasFocus) return _TargetField.peso;
    return _TargetField.nombre;
  }

  TextEditingController _controllerFor(_TargetField field) {
    switch (field) {
      case _TargetField.barcode:
        return _barcodeController;
      case _TargetField.nombre:
        return _nombreController;
      case _TargetField.telefono:
        return _telefonoController;
      case _TargetField.peso:
        return _pesoController;
      case _TargetField.ventanilla:
        return _nombreController;
    }
  }

  void _focusMissingField(_TargetField? field) {
    if (field == null) return;
    switch (field) {
      case _TargetField.barcode:
        _barcodeFocusNode.requestFocus();
        break;
      case _TargetField.nombre:
        _nombreFocusNode.requestFocus();
        break;
      case _TargetField.telefono:
        _telefonoFocusNode.requestFocus();
        break;
      case _TargetField.peso:
        _pesoFocusNode.requestFocus();
        break;
      case _TargetField.ventanilla:
        FocusScope.of(context).unfocus();
        break;
    }
    _scheduleEnsureFieldVisible(field, immediate: true);
  }

  _TargetField? _targetFieldFromKey(String? key) {
    switch (key) {
      case ScanConfirmFieldKeys.ventanilla:
        return _TargetField.ventanilla;
      case ScanConfirmFieldKeys.barcode:
        return _TargetField.barcode;
      case ScanConfirmFieldKeys.nombre:
        return _TargetField.nombre;
      case ScanConfirmFieldKeys.telefono:
        return _TargetField.telefono;
      case ScanConfirmFieldKeys.peso:
        return _TargetField.peso;
    }
    return null;
  }

  void _appendToken(String token) {
    final state = _overlayState.value;
    final controller = _controllerFor(state.activeField);
    final current = controller.text.trim();

    final normalizedToken = switch (state.activeField) {
      _TargetField.telefono => token.replaceAll(RegExp(r'\D'), ''),
      _TargetField.peso => token.replaceAll(RegExp(r'[^0-9.,]'), ''),
      _ => token.toUpperCase(),
    };

    if (normalizedToken.isEmpty) return;

    final next = current.isEmpty
        ? normalizedToken
        : '$current $normalizedToken';
    controller.text = next;
    controller.selection = TextSelection.fromPosition(
      TextPosition(offset: controller.text.length),
    );

    final updatedTokens = [...state.ocrTokens]..remove(token);
    _updateOverlayState((currentState) {
      return currentState.copyWith(
        ocrTokens: List<String>.unmodifiable(updatedTokens),
      );
    });
  }

  void _toggleSuggestions() {
    _updateOverlayState((state) {
      if (state.ocrTokens.isEmpty) {
        _showTopMessage('No hay palabras OCR disponibles.');
        return state;
      }
      return state.copyWith(showSuggestions: !state.showSuggestions);
    });
  }

  void _showTopMessage(
    String message, {
    AppFeedbackTone tone = AppFeedbackTone.info,
  }) {
    if (!mounted) return;
    showAppFeedbackBanner(context, message, tone: tone);
  }

  _ValidationResult _validateAndBuildResult() {
    final header = _headerState.value;
    final fields = _fieldsState.value;

    final barcode = _barcodeController.text.trim().toUpperCase();
    final nombre = _nombreController.text.trim().toUpperCase();
    final telefono = _telefonoController.text.trim().replaceAll(
      RegExp(r'\D'),
      '',
    );
    const observaciones = '';
    final pesoRaw = _pesoController.text.trim();
    final selectedVentanillaId = fields.selectedVentanillaId;
    final validation = ScanConfirmValidator.validate(
      ventanillaId: selectedVentanillaId,
      barcode: barcode,
      nombre: nombre,
      telefono: telefono,
      pesoRaw: pesoRaw,
    );
    if (!validation.isValid) {
      return _ValidationResult.error(
        validation.errorMessage ?? AppStrings.errorPesoNumeric,
        targetField: _targetFieldFromKey(validation.fieldKey),
      );
    }
    final peso = validation.peso ?? 0;
    final ventanillaId =
        selectedVentanillaId ??
        (throw StateError('Ventanilla requerida para guardar.'));

    final ventanillaNombre = _selectedVentanillaNombre(
      ventanillaId,
      fields.ventanillas,
    );

    return _ValidationResult.success(
      ScanResult(
        barcodeText: barcode,
        nombre: nombre,
        telefono: telefono,
        peso: peso,
        ciudad: fields.selectedCiudad,
        zona: '',
        aduana: fields.isAduana,
        ventanillaId: ventanillaId,
        ventanillaNombre: ventanillaNombre,
        tipoDocumento: header.selectedTipoDocumento,
        observaciones: observaciones,
        createdAt: DateTime.now(),
      ),
    );
  }

  String _selectedVentanillaNombre(
    int selectedId,
    List<VentanillaOption> options,
  ) {
    for (final option in options) {
      if (option.id == selectedId) return option.label;
    }
    return '';
  }

  Future<void> _confirmAndReturn() async {
    final state = _overlayState.value;
    if (state.confirming || state.saveDialogVisible || !mounted) return;

    final validation = _validateAndBuildResult();
    if (validation.errorMessage != null) {
      _updateFieldsState(
        (current) => current.copyWith(showValidationErrors: true),
      );
      _showTopMessage(validation.errorMessage!, tone: AppFeedbackTone.error);
      _focusMissingField(validation.targetField);
      return;
    }

    final result = validation.result!;

    FocusScope.of(context).unfocus();
    _updateOverlayState((current) {
      return current.copyWith(
        saveDialogVisible: true,
        keyboardUiVisible: false,
        showSuggestions: false,
      );
    });

    final shouldSave = await _showSaveConfirmationDialog(result);

    if (!mounted) return;
    if (shouldSave != true) {
      _updateOverlayState(
        (current) => current.copyWith(saveDialogVisible: false),
      );
      return;
    }

    _updateOverlayState(
      (current) => current.copyWith(saveDialogVisible: false, confirming: true),
    );

    var savingDialogShown = false;
    if (mounted) {
      savingDialogShown = true;
      showDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (dialogContext) {
          return PopScope(
            canPop: false,
            child: Dialog(
              elevation: 18,
              backgroundColor: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 22,
                ),
                decoration: AppTheme.buildDialogDecoration(),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 3.2,
                        color: AppTheme.blue,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Guardando información...',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.blue,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Espera un momento',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.blue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    var saveSuccess = false;
    String? saveErrorMessage;
    try {
      await widget.scanRepository.saveScan(result).timeout(_saveTimeout);
      saveSuccess = true;
    } on TimeoutException {
      saveErrorMessage =
          'Está tardando más de lo esperado. Revisa tu internet e intenta otra vez.';
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error saving scan: $e');
      }
      final message = e.toString().toUpperCase();
      if (e is StateError && e.message == 'PAQUETE_YA_CLASIFICADO') {
        saveErrorMessage = 'Este paquete ya había sido registrado.';
      } else if (e is StateError && e.message == 'CODIGO_BARRA_INVALIDO') {
        saveErrorMessage =
            'El código escaneado no se pudo leer bien. Intenta nuevamente.';
      } else if (e is StateError &&
          e.message == 'TABLA_DESTINO_NO_ENCONTRADA') {
        saveErrorMessage =
            'No pudimos encontrar dónde guardar este paquete. Intenta nuevamente.';
      } else if (message.contains('TIMEOUT')) {
        saveErrorMessage =
            'Está tardando más de lo esperado. Intenta guardarlo otra vez.';
      } else {
        saveErrorMessage = UserFriendlyErrorMapper.message(
          e,
          fallback:
              'No pudimos guardar la información. Intenta nuevamente en un momento.',
        );
      }
    } finally {
      if (mounted) {
        if (savingDialogShown) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        _updateOverlayState((current) => current.copyWith(confirming: false));
        if (saveErrorMessage != null) {
          _showTopMessage(saveErrorMessage, tone: AppFeedbackTone.error);
        }
      }
    }

    if (saveSuccess && mounted) {
      widget.onSaved?.call(result);
      Navigator.of(context).pop();
    }
  }

  Future<bool?> _showSaveConfirmationDialog(ScanResult result) {
    final resumen = <String>[
      'Codigo: ${result.barcodeText}',
      'Nombre: ${result.nombre}',
      'Teléfono: ${result.telefono}',
      'Ciudad: ${result.ciudad}',
      'Aduana: ${result.aduana ? 'SI' : 'NO'}',
      'Ventanilla: ${result.ventanillaNombre}',
      'Tipo: ${result.tipoDocumento}',
    ];

    return showGeneralDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierLabel: 'confirmar-guardado',
      barrierColor: AppTheme.dialogBarrier,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 360),
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                  decoration: AppTheme.buildDialogDecoration(
                    borderRadius: AppTheme.radiusMedium,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Confirmar guardado',
                        style: TextStyle(
                          color: AppTheme.blue,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Se guardarán estos datos:\n\n${resumen.join('\n')}',
                        style: const TextStyle(
                          color: AppTheme.blue,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.blue,
                            ),
                            child: const Text('Cancelar'),
                          ),
                          const SizedBox(width: 8),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: AppTheme.actionGradient,
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x220F1E3D),
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(98, 40),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 0,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              child: const Text('Guardar'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('Confirmar Datos Escaneados'),
        backgroundColor: AppTheme.yellow,
        foregroundColor: AppTheme.blue,
        elevation: 0,
      ),
      body: Stack(
        children: [
          RepaintBoundary(
            child: Container(
              decoration: const BoxDecoration(
                gradient: AppTheme.warmPageGradient,
              ),
              child: CustomScrollView(
                controller: _scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.manual,
                cacheExtent: 120,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 240),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate.fixed([
                        ValueListenableBuilder<_ScanConfirmHeaderState>(
                          valueListenable: _headerState,
                          builder: (context, state, _) {
                            return ScanConfirmHeaderCard(
                              tipoDocumento: state.selectedTipoDocumento,
                              clasificacion: state.clasificacion,
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        RepaintBoundary(
                          child:
                              ValueListenableBuilder<_ScanConfirmFieldsState>(
                                valueListenable: _fieldsState,
                                builder: (context, state, _) {
                                  return _buildFieldsBlock(state);
                                },
                              ),
                        ),
                        const SizedBox(height: 12),
                        RepaintBoundary(
                          child: ScanConfirmOcrSection(
                            ocrRaw: widget.data.ocrRaw,
                          ),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ValueListenableBuilder<_ScanConfirmOverlayState>(
            valueListenable: _overlayState,
            builder: (context, state, _) => _buildKeyboardOverlay(state),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyboardOverlay(_ScanConfirmOverlayState state) {
    return ScanConfirmKeyboardOverlay(
      ocrTokens: state.ocrTokens,
      confirming: state.confirming,
      saveDialogVisible: state.saveDialogVisible,
      showSuggestions: state.showSuggestions,
      maxVisibleSuggestionTokens: _maxVisibleSuggestionTokens,
      onConfirm: _confirmAndReturn,
      onAppendToken: _appendToken,
      onToggleSuggestions: _toggleSuggestions,
    );
  }

  Widget _buildFieldsBlock(_ScanConfirmFieldsState state) {
    return ScanConfirmFieldsSection(
      barcodeController: _barcodeController,
      nombreController: _nombreController,
      telefonoController: _telefonoController,
      pesoController: _pesoController,
      barcodeFocusNode: _barcodeFocusNode,
      nombreFocusNode: _nombreFocusNode,
      telefonoFocusNode: _telefonoFocusNode,
      pesoFocusNode: _pesoFocusNode,
      selectedCiudad: state.selectedCiudad,
      tipoDocumentoListenable: _tipoDocumentoNotifier,
      isAduana: state.isAduana,
      loadingVentanillas: state.loadingVentanillas,
      ventanillas: state.ventanillas,
      selectedVentanillaId: state.selectedVentanillaId,
      showValidationErrors: state.showValidationErrors,
      departamentos: _departamentos,
      tipoDocumentoOpciones: _tipoDocumentoOpciones,
      onCiudadChanged: (value) {
        _updateFieldsState(
          (current) => current.copyWith(selectedCiudad: value),
        );
      },
      onTipoDocumentoChanged: (value) {
        if (_tipoDocumentoNotifier.value != value) {
          _tipoDocumentoNotifier.value = value;
        }
        _updateHeaderState(
          (current) => current.copyWith(selectedTipoDocumento: value),
        );
      },
      onAduanaChanged: (value) {
        _updateFieldsState((current) => current.copyWith(isAduana: value));
      },
      onVentanillaChanged: (value) {
        _updateFieldsState(
          (current) => current.copyWith(selectedVentanillaId: value),
        );
      },
      barcodeFieldKey: _barcodeFieldKey,
      nombreFieldKey: _nombreFieldKey,
      telefonoFieldKey: _telefonoFieldKey,
      pesoFieldKey: _pesoFieldKey,
      ventanillaFieldKey: _ventanillaFieldKey,
    );
  }
}

class _ScanConfirmHeaderState {
  const _ScanConfirmHeaderState({
    required this.clasificacion,
    required this.selectedTipoDocumento,
  });

  final String clasificacion;
  final String selectedTipoDocumento;

  _ScanConfirmHeaderState copyWith({
    String? clasificacion,
    String? selectedTipoDocumento,
  }) {
    return _ScanConfirmHeaderState(
      clasificacion: clasificacion ?? this.clasificacion,
      selectedTipoDocumento:
          selectedTipoDocumento ?? this.selectedTipoDocumento,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _ScanConfirmHeaderState &&
        other.clasificacion == clasificacion &&
        other.selectedTipoDocumento == selectedTipoDocumento;
  }

  @override
  int get hashCode => Object.hash(clasificacion, selectedTipoDocumento);
}

class _ScanConfirmFieldsState {
  const _ScanConfirmFieldsState({
    required this.selectedCiudad,
    required this.isAduana,
    required this.loadingVentanillas,
    required this.ventanillas,
    required this.selectedVentanillaId,
    required this.showValidationErrors,
  });

  final String selectedCiudad;
  final bool isAduana;
  final bool loadingVentanillas;
  final List<VentanillaOption> ventanillas;
  final int? selectedVentanillaId;
  final bool showValidationErrors;

  _ScanConfirmFieldsState copyWith({
    String? selectedCiudad,
    bool? isAduana,
    bool? loadingVentanillas,
    List<VentanillaOption>? ventanillas,
    Object? selectedVentanillaId = _ScanConfirmPageState._unset,
    bool? showValidationErrors,
  }) {
    return _ScanConfirmFieldsState(
      selectedCiudad: selectedCiudad ?? this.selectedCiudad,
      isAduana: isAduana ?? this.isAduana,
      loadingVentanillas: loadingVentanillas ?? this.loadingVentanillas,
      ventanillas: ventanillas ?? this.ventanillas,
      selectedVentanillaId: selectedVentanillaId == _ScanConfirmPageState._unset
          ? this.selectedVentanillaId
          : selectedVentanillaId as int?,
      showValidationErrors: showValidationErrors ?? this.showValidationErrors,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _ScanConfirmFieldsState &&
        other.selectedCiudad == selectedCiudad &&
        other.isAduana == isAduana &&
        other.loadingVentanillas == loadingVentanillas &&
        listEquals(other.ventanillas, ventanillas) &&
        other.selectedVentanillaId == selectedVentanillaId &&
        other.showValidationErrors == showValidationErrors;
  }

  @override
  int get hashCode => Object.hash(
    selectedCiudad,
    isAduana,
    loadingVentanillas,
    Object.hashAll(ventanillas),
    selectedVentanillaId,
    showValidationErrors,
  );
}

class _ScanConfirmOverlayState {
  const _ScanConfirmOverlayState({
    required this.confirming,
    required this.saveDialogVisible,
    required this.showSuggestions,
    required this.keyboardUiVisible,
    required this.ocrTokens,
    required this.activeField,
  });

  final bool confirming;
  final bool saveDialogVisible;
  final bool showSuggestions;
  final bool keyboardUiVisible;
  final List<String> ocrTokens;
  final _TargetField activeField;

  _ScanConfirmOverlayState copyWith({
    bool? confirming,
    bool? saveDialogVisible,
    bool? showSuggestions,
    bool? keyboardUiVisible,
    List<String>? ocrTokens,
    _TargetField? activeField,
  }) {
    return _ScanConfirmOverlayState(
      confirming: confirming ?? this.confirming,
      saveDialogVisible: saveDialogVisible ?? this.saveDialogVisible,
      showSuggestions: showSuggestions ?? this.showSuggestions,
      keyboardUiVisible: keyboardUiVisible ?? this.keyboardUiVisible,
      ocrTokens: ocrTokens ?? this.ocrTokens,
      activeField: activeField ?? this.activeField,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _ScanConfirmOverlayState &&
        other.confirming == confirming &&
        other.saveDialogVisible == saveDialogVisible &&
        other.showSuggestions == showSuggestions &&
        other.keyboardUiVisible == keyboardUiVisible &&
        listEquals(other.ocrTokens, ocrTokens) &&
        other.activeField == activeField;
  }

  @override
  int get hashCode => Object.hash(
    confirming,
    saveDialogVisible,
    showSuggestions,
    keyboardUiVisible,
    Object.hashAll(ocrTokens),
    activeField,
  );
}

class _ValidationResult {
  const _ValidationResult._({this.result, this.errorMessage, this.targetField});

  const _ValidationResult.success(ScanResult result)
    : this._(result: result, errorMessage: null);

  const _ValidationResult.error(
    String errorMessage, {
    _TargetField? targetField,
  }) : this._(
         result: null,
         errorMessage: errorMessage,
         targetField: targetField,
       );

  final ScanResult? result;
  final String? errorMessage;
  final _TargetField? targetField;
}
