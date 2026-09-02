import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scan_agbc/nucleo/componentes/app_feedback_banner.dart';
import 'package:scan_agbc/funcionalidades/autenticacion/dominio/modelos/authenticated_user.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/presentacion/controladores/scanner_controller.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/dominio/modelos/scan_result.dart';
import 'package:scan_agbc/nucleo/inyeccion/app_services.dart';
import 'package:scan_agbc/nucleo/tema/app_theme.dart';
import 'package:scan_agbc/nucleo/utilidades/user_friendly_error_mapper.dart';
import 'package:scan_agbc/funcionalidades/autenticacion/presentacion/paginas/login_page.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/presentacion/paginas/gallery_roi_page.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/presentacion/paginas/scan_confirm_page.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/presentacion/componentes/escaner/profile_drawer.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/presentacion/componentes/escaner/scanner_body.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/presentacion/componentes/escaner/torch_action_button.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/utilidades/package_code_classifier.dart';

enum ScannerPageMode { ficha, packageLookup }

class ScannerPage extends StatefulWidget {
  const ScannerPage({
    super.key,
    required this.controller,
    required this.services,
    required this.currentUser,
    this.mode = ScannerPageMode.ficha,
    this.disposeControllerOnClose = true,
    this.collectMultiplePackageCodes = false,
    this.availablePackageCodes = const <String>{},
    this.initiallySelectedPackageCodes = const <String>{},
    this.onSelectedPackageCodesChanged,
    this.onReviewPackageCodes,
  });

  final ScannerController controller;
  final AppServices services;
  final AuthenticatedUser currentUser;
  final ScannerPageMode mode;
  final bool disposeControllerOnClose;
  final bool collectMultiplePackageCodes;
  final Set<String> availablePackageCodes;
  final Set<String> initiallySelectedPackageCodes;
  final ValueChanged<Set<String>>? onSelectedPackageCodesChanged;
  final Future<List<String>?> Function(List<String> selectedCodes)?
  onReviewPackageCodes;

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _lineController;
  final ImagePicker _imagePicker = ImagePicker();
  late final _sessionSecurityService = widget.services.sessionSecurityService;
  late final _biometricAuthService = widget.services.biometricAuthService;
  late final String _displayName;
  bool _rememberSession = false;
  bool _useBiometric = false;
  bool _biometricAvailable = false;
  bool _scanActionLocked = false;
  bool _packageLookupCompleted = false;
  PackageLookupRecognitionMode _packageRecognitionMode =
      PackageLookupRecognitionMode.barcode;
  final Set<String> _collectedPackageCodes = <String>{};
  final Set<String> _rejectedPackageCodes = <String>{};
  final List<String> _recentCodes = [];
  String? _lastAddedBarcodeSnapshot;
  SharedPreferences? _prefs;
  Timer? _persistRecentCodesTimer;
  bool _recentCodesDirty = false;

  static const String _recentCodesKey = 'scanner_recent_codes';
  static const int _recentCodesLimit = 3;

  bool get _isPackageLookupMode => widget.mode == ScannerPageMode.packageLookup;
  bool get _isBatchPackageLookup =>
      _isPackageLookupMode && widget.collectMultiplePackageCodes;
  bool get _usesOcrLookup =>
      _packageRecognitionMode == PackageLookupRecognitionMode.ocr;

  @override
  void initState() {
    super.initState();
    _displayName = widget.currentUser.name.trim().isEmpty
        ? widget.currentUser.email
        : widget.currentUser.name.trim();
    _lineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _loadSecurityPreferences();
    _loadRecentCodes();
    if (_isBatchPackageLookup) {
      _collectedPackageCodes.addAll(
        widget.initiallySelectedPackageCodes
            .map(PackageCodeClassifier.normalize)
            .where(widget.availablePackageCodes.contains),
      );
    }
    if (_isPackageLookupMode) {
      widget.controller.prepareCamera();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_startPackageLookupAutoScan());
        }
      });
    }
  }

  @override
  void dispose() {
    _persistRecentCodesTimer?.cancel();
    if (_recentCodesDirty) {
      unawaited(_flushRecentCodes());
    }
    _lineController.dispose();
    if (widget.disposeControllerOnClose) {
      widget.controller.dispose();
    } else if (_isPackageLookupMode) {
      unawaited(widget.controller.releaseCamera());
    }
    super.dispose();
  }

  Future<void> _startPackageLookupAutoScan() async {
    if (!_isPackageLookupMode || _packageLookupCompleted) return;
    await widget.controller.startPackageLookupAutoScan(
      onCodeDetected: _handleAutomaticPackageCode,
      recognitionMode: _packageRecognitionMode,
      canDetectCode: _isBatchPackageLookup
          ? (code) {
              final normalizedCode = PackageCodeClassifier.normalize(code);
              return !_collectedPackageCodes.contains(normalizedCode) &&
                  !_rejectedPackageCodes.contains(normalizedCode);
            }
          : null,
    );
  }

  void _handleAutomaticPackageCode(String code) {
    if (!mounted || _packageLookupCompleted || _scanActionLocked) return;
    if (!_usesOcrLookup) {
      unawaited(_confirmBarcodePackageCode(code));
      return;
    }
    unawaited(_confirmOcrPackageCode(code));
  }

  Future<void> _confirmBarcodePackageCode(String code) async {
    if (!mounted || _packageLookupCompleted || _scanActionLocked) return;

    _scanActionLocked = true;
    try {
      await _acceptBarcodePackageCode(code);
    } finally {
      _scanActionLocked = false;
      _resumePackageLookupAutoScanIfNeeded();
    }
  }

  Future<void> _acceptBarcodePackageCode(String rawCode) async {
    final validation = PackageCodeClassifier.validateForSearch(rawCode);
    if (!validation.isValid || validation.normalizedCode.isEmpty) {
      showAppFeedbackBanner(
        context,
        'No se pudo reconocer un código de barras válido.',
        tone: AppFeedbackTone.error,
      );
      return;
    }

    if (_isBatchPackageLookup) {
      await _acceptBatchPackageCode(validation.normalizedCode);
      return;
    }

    _rememberDetectedPackageCode(validation.normalizedCode);
    _packageLookupCompleted = true;
    Navigator.of(context).pop(validation.normalizedCode);
  }

  Future<void> _confirmOcrPackageCode(String code) async {
    if (!mounted || _packageLookupCompleted || _scanActionLocked) return;

    _scanActionLocked = true;
    try {
      await _showPackageLookupResultModal(detectedCode: code);
    } finally {
      _scanActionLocked = false;
      _resumePackageLookupAutoScanIfNeeded();
    }
  }

  void _resumePackageLookupAutoScanIfNeeded() {
    if (!_isPackageLookupMode || _packageLookupCompleted || !mounted) return;
    unawaited(_startPackageLookupAutoScan());
  }

  void _publishPackageSelection() {
    widget.onSelectedPackageCodesChanged?.call(
      Set<String>.unmodifiable(_collectedPackageCodes),
    );
  }

  Future<void> _changePackageRecognitionMode(
    PackageLookupRecognitionMode mode,
  ) async {
    if (!_isPackageLookupMode ||
        _scanActionLocked ||
        mode == _packageRecognitionMode) {
      return;
    }

    _scanActionLocked = true;
    try {
      await widget.controller.stopPackageLookupAutoScan();
      if (!mounted) return;
      setState(() {
        _packageRecognitionMode = mode;
      });
      widget.controller.clearScanOutput(
        statusMessage: mode == PackageLookupRecognitionMode.barcode
            ? 'Enfoca el código de barras dentro del marco.'
            : 'Enfoca los caracteres impresos dentro del marco.',
      );
    } finally {
      _scanActionLocked = false;
      _resumePackageLookupAutoScanIfNeeded();
    }
  }

  bool _addPackageCodeToBatch(String rawCode) {
    final validation = PackageCodeClassifier.validateForSearch(rawCode);
    final normalizedCode = validation.normalizedCode;
    if (!validation.isValid || normalizedCode.isEmpty) {
      showAppFeedbackBanner(
        context,
        validation.errorMessage ?? 'Revisa el código e intenta nuevamente.',
        tone: AppFeedbackTone.error,
      );
      return false;
    }

    if (_isBatchPackageLookup &&
        widget.availablePackageCodes.isNotEmpty &&
        !widget.availablePackageCodes.contains(normalizedCode)) {
      _rejectedPackageCodes.add(normalizedCode);
      showAppFeedbackBanner(
        context,
        'Este paquete no está disponible para asignar.',
        tone: AppFeedbackTone.error,
      );
      return false;
    }

    if (_collectedPackageCodes.contains(normalizedCode)) {
      showAppFeedbackBanner(
        context,
        'Este paquete ya esta guardado en la lista.',
        tone: AppFeedbackTone.info,
      );
      return false;
    }

    setState(() {
      _collectedPackageCodes.add(normalizedCode);
    });
    _publishPackageSelection();
    HapticFeedback.mediumImpact();
    _rememberDetectedPackageCode(normalizedCode);
    return true;
  }

  Future<void> _acceptBatchPackageCode(String rawCode) async {
    if (!_addPackageCodeToBatch(rawCode) || !mounted) return;

    final continueSearching = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final normalizedCode = PackageCodeClassifier.normalize(rawCode);
        return AlertDialog(
          icon: const Icon(
            Icons.check_circle_rounded,
            color: AppTheme.successGreen,
            size: 58,
          ),
          title: const Text('Paquete seleccionado'),
          content: Text(
            '$normalizedCode se agregará a la lista de asignación.',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actionsOverflowAlignment: OverflowBarAlignment.center,
          actionsOverflowButtonSpacing: 8,
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(126, 52),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: const Text('Finalizar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                minimumSize: const Size(126, 52),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: const Text('Agregar +'),
            ),
          ],
        );
      },
    );

    if (!mounted || continueSearching != false) return;
    await _finishBatchPackageLookup();
  }

  Future<void> _finishBatchPackageLookup() async {
    if (_collectedPackageCodes.isEmpty || _packageLookupCompleted) return;
    _packageLookupCompleted = true;
    await widget.controller.stopPackageLookupAutoScan();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pop<List<String>>(List<String>.unmodifiable(_collectedPackageCodes));
  }

  Future<void> _reviewBatchPackageSelection() async {
    final onReviewPackageCodes = widget.onReviewPackageCodes;
    if (_scanActionLocked ||
        _collectedPackageCodes.isEmpty ||
        onReviewPackageCodes == null) {
      return;
    }

    _scanActionLocked = true;
    try {
      await widget.controller.stopPackageLookupAutoScan();
      final reviewedCodes = await onReviewPackageCodes(
        _collectedPackageCodes.toList(growable: false),
      );
      if (!mounted || reviewedCodes == null) return;

      final normalizedCodes = reviewedCodes
          .map(PackageCodeClassifier.normalize)
          .where(widget.availablePackageCodes.contains)
          .toSet();
      setState(() {
        _collectedPackageCodes
          ..clear()
          ..addAll(normalizedCodes);
      });
      _publishPackageSelection();
    } finally {
      _scanActionLocked = false;
      _resumePackageLookupAutoScanIfNeeded();
    }
  }

  void _logout() {
    unawaited(_logoutAsync());
  }

  Future<void> _logoutAsync() async {
    await widget.services.clearActiveSession();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginPage(services: widget.services)),
      (route) => false,
    );
  }

  Future<void> _loadSecurityPreferences() async {
    await _sessionSecurityService.setRememberSessionEnabled(true);
    const rememberSessionEnabled = true;
    final savedEmail = await _sessionSecurityService.readSessionEmail();
    final biometricEnabled = await _sessionSecurityService
        .isBiometricEnabledFor(widget.currentUser.alias);
    final biometricAvailable = await _biometricAuthService.isAvailable();

    if (rememberSessionEnabled &&
        (savedEmail == null || savedEmail.trim().isEmpty)) {
      await _sessionSecurityService.saveSessionEmail(widget.currentUser.alias);
    }

    if (!mounted) return;
    setState(() {
      _rememberSession = rememberSessionEnabled;
      _useBiometric = _rememberSession && biometricEnabled;
      _biometricAvailable = biometricAvailable;
    });
  }

  Future<void> _setRememberSession(bool enabled) async {
    if (enabled) {
      await _sessionSecurityService.setRememberSessionEnabled(true);
      await _sessionSecurityService.saveSessionEmail(widget.currentUser.alias);
      await widget.services.persistRememberedAuthState(widget.currentUser);
      if (!mounted) return;
      setState(() {
        _rememberSession = true;
      });
      return;
    }

    await _sessionSecurityService.clearSession();
    if (!mounted) return;
    setState(() {
      _rememberSession = false;
      _useBiometric = false;
    });
  }

  Future<void> _setUseBiometric(bool enabled) async {
    if (!_rememberSession) return;
    if (!_biometricAvailable && enabled) {
      if (mounted) {
        showAppFeedbackBanner(
          context,
          'Este dispositivo no tiene huella disponible.',
          tone: AppFeedbackTone.info,
        );
      }
      return;
    }

    await _sessionSecurityService.setBiometricEnabledFor(
      widget.currentUser.alias,
      enabled,
    );
    if (!mounted) return;
    setState(() {
      _useBiometric = enabled;
    });
  }

  Future<void> _scanFromGalleryWithCrop() async {
    if (_scanActionLocked) return;
    final controller = widget.controller;
    if (controller.isProcessing) return;

    _scanActionLocked = true;
    try {
      if (_isPackageLookupMode) {
        await controller.stopPackageLookupAutoScan();
      }
      final image = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (!mounted || image == null) return;
      if (_isPackageLookupMode) {
        controller.clearScanOutput(
          statusMessage: 'Estamos leyendo la imagen de la galeria...',
        );
        await controller.scanFichaFromImagePath(
          image.path,
          useRoiFiltering: false,
          packageLookupMode: true,
          packageLookupRecognitionMode: _packageRecognitionMode,
        );
        if (!mounted) return;
        await _handlePackageLookupScanResult();
        return;
      }
      await _openRoiSelectionFlow(
        imagePath: image.path,
        controller: controller,
      );
    } finally {
      _scanActionLocked = false;
      _resumePackageLookupAutoScanIfNeeded();
    }
  }

  Future<void> _openRoiSelectionFlow({
    required String imagePath,
    required ScannerController controller,
  }) async {
    final hasSelection =
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => GalleryRoiPage(
              imagePath: imagePath,
              controller: controller,
              barcodeOnly: false,
            ),
          ),
        ) ==
        true;
    if (!hasSelection || !mounted) return;
    await _openScanConfirmPage();
  }

  Future<String?> _captureCameraImagePath(ScannerController controller) async {
    final cameraController = controller.cameraController;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return null;
    }

    try {
      final photo = await cameraController.takePicture();
      return photo.path;
    } catch (_) {
      if (mounted) {
        showAppFeedbackBanner(
          context,
          'No pudimos tomar la foto. Intenta nuevamente.',
          tone: AppFeedbackTone.error,
        );
      }
      return null;
    }
  }

  Future<void> _deleteTempCapture(String imagePath) async {
    try {
      final file = File(imagePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Ignore temporary capture cleanup failures.
    }
  }

  Future<void> _scanFromCameraAndShowModal() async {
    if (_scanActionLocked) return;
    final controller = widget.controller;
    if (controller.isProcessing) return;

    if (!controller.cameraReady) {
      _scanActionLocked = true;
      try {
        await controller.initCamera();
        if (!mounted) return;
        if (controller.cameraReady) {
          showAppFeedbackBanner(
            context,
            'La cámara está lista.',
            tone: AppFeedbackTone.info,
          );
        } else {
          showAppFeedbackBanner(
            context,
            UserFriendlyErrorMapper.message(
              controller.status,
              fallback: 'No pudimos preparar la cámara. Intenta nuevamente.',
            ),
            tone: AppFeedbackTone.error,
          );
          if (controller.cameraPermissionDenied) {
            await _showCameraPermissionHelpDialog();
          }
        }
      } finally {
        _scanActionLocked = false;
        _resumePackageLookupAutoScanIfNeeded();
      }
      return;
    }
    _scanActionLocked = true;
    try {
      if (_isPackageLookupMode) {
        await controller.stopPackageLookupAutoScan();
      }
      final imagePath = await _captureCameraImagePath(controller);
      if (imagePath == null || !mounted) return;
      try {
        if (_isPackageLookupMode) {
          controller.clearScanOutput(
            statusMessage: 'Estamos leyendo la foto...',
          );
          await controller.scanFichaFromImagePath(
            imagePath,
            useRoiFiltering: true,
            packageLookupMode: true,
            packageLookupRecognitionMode: _packageRecognitionMode,
          );
          if (!mounted) return;
          await _handlePackageLookupScanResult();
          return;
        }
        await _openRoiSelectionFlow(
          imagePath: imagePath,
          controller: controller,
        );
      } finally {
        await _deleteTempCapture(imagePath);
      }
    } finally {
      _scanActionLocked = false;
      _resumePackageLookupAutoScanIfNeeded();
    }
  }

  Future<void> _showCameraPermissionHelpDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Permiso de cámara'),
          content: const Text(
            'Para usar esta función, activa el permiso de cámara en los ajustes del dispositivo.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Entendido'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handlePackageLookupScanResult() async {
    final detectedCode = _extractDetectedPackageCode();
    if (detectedCode == null) {
      showAppFeedbackBanner(
        context,
        _usesOcrLookup
            ? 'No se reconocieron caracteres suficientes. Ajusta el enfoque e intenta nuevamente.'
            : 'No se pudo reconocer un código de barras válido.',
        tone: AppFeedbackTone.error,
      );
      return;
    }

    if (_usesOcrLookup) {
      await _showPackageLookupResultModal(detectedCode: detectedCode);
    } else {
      await _acceptBarcodePackageCode(detectedCode);
    }
  }

  Future<void> _showPackageLookupResultModal({String? detectedCode}) async {
    final code = detectedCode ?? _extractDetectedPackageCode();
    if (code == null) {
      if (mounted) {
        showAppFeedbackBanner(
          context,
          'No se pudo reconocer un código válido.',
          tone: AppFeedbackTone.error,
        );
      }
      return;
    }

    final dialogDisposed = Completer<void>();
    final selectedCode = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OcrCodeVerificationDialog(
        initialCode: code,
        onDisposed: () {
          if (!dialogDisposed.isCompleted) dialogDisposed.complete();
        },
      ),
    );
    await dialogDisposed.future;

    final validation = PackageCodeClassifier.validateForSearch(
      selectedCode ?? '',
    );
    final normalizedCode = validation.normalizedCode;
    if (!mounted || selectedCode == null) {
      return;
    }

    if (!validation.isValid || normalizedCode.isEmpty) {
      showAppFeedbackBanner(
        context,
        validation.errorMessage ?? 'Revisa el código e intenta nuevamente.',
        tone: AppFeedbackTone.error,
      );
      return;
    }

    if (_isBatchPackageLookup) {
      await _acceptBatchPackageCode(normalizedCode);
      return;
    }
    _rememberDetectedPackageCode(normalizedCode);
    _packageLookupCompleted = true;
    Navigator.of(context).pop(normalizedCode);
  }

  Future<void> _showManualPackageCodeInput() async {
    final dialogDisposed = Completer<void>();
    final rawCode = await showDialog<String>(
      context: context,
      builder: (_) => _ManualPackageCodeDialog(
        onDisposed: () {
          if (!dialogDisposed.isCompleted) dialogDisposed.complete();
        },
      ),
    );
    await dialogDisposed.future;

    final code = PackageCodeClassifier.normalize(rawCode ?? '');
    if (!mounted || code.isEmpty) return;

    if (_isBatchPackageLookup) {
      await _acceptBatchPackageCode(code);
      return;
    }
    _rememberDetectedPackageCode(code);
    _packageLookupCompleted = true;
    Navigator.of(context).pop(code);
  }

  Future<void> _openScanConfirmPage() async {
    final scannerController = widget.controller;
    _captureRecentCodes();
    final cameraController = scannerController.cameraController;
    final canPausePreview =
        cameraController != null && cameraController.value.isInitialized;

    if (canPausePreview) {
      try {
        await cameraController.pausePreview();
      } catch (_) {
        // Continue even if preview pause is not supported on the device.
      }
    }

    try {
      if (!mounted || !scannerController.hasDetectedContent) return;
      if (scannerController.lastData == null) {
        if (mounted) {
          showAppFeedbackBanner(
            context,
            'No pudimos preparar la información escaneada. Intenta nuevamente.',
            tone: AppFeedbackTone.error,
          );
        }
        return;
      }
      await Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              ScanConfirmPage(
                data: scannerController.lastData!,
                scanRepository: scannerController.scanRepository,
                onSaved: _addConfirmedResult,
              ),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
    } finally {
      if (mounted && canPausePreview) {
        try {
          await cameraController.resumePreview();
        } catch (_) {
          // Ignore resume failures to avoid blocking navigation return.
        }
      }
    }
  }

  void _captureRecentCodes() {
    final raw = widget.controller.barcodeResult.trim();
    if (raw.isEmpty || raw == 'Sin detectar') return;
    if (raw == _lastAddedBarcodeSnapshot) return;
    _lastAddedBarcodeSnapshot = raw;

    final codes = raw
        .split('\n')
        .map((code) => code.trim())
        .where((code) => code.isNotEmpty)
        .toList();
    _insertRecentCodes(codes);
  }

  void _rememberDetectedPackageCode(String code) {
    final normalized = code.trim();
    if (normalized.isEmpty) return;
    if (_lastAddedBarcodeSnapshot == normalized) return;
    _lastAddedBarcodeSnapshot = normalized;
    _insertRecentCodes([normalized]);
  }

  String? _extractDetectedPackageCode() {
    if (!_usesOcrLookup) {
      return _extractPackageCodeFromText(widget.controller.barcodeResult);
    }

    final rawText = widget.controller.ocrResult;
    if (rawText == 'Sin detectar') return null;
    final normalizedText = PackageCodeClassifier.normalize(rawText);
    return normalizedText.isEmpty ? null : normalizedText;
  }

  String? _extractPackageCodeFromText(String rawValue) {
    final validation = PackageCodeClassifier.validateForSearch(rawValue);
    if (!validation.isValid || validation.normalizedCode.isEmpty) return null;
    return validation.normalizedCode;
  }

  void _insertRecentCodes(List<String> codes) {
    if (codes.isEmpty) return;

    setState(() {
      for (final code in codes) {
        _recentCodes.remove(code);
        _recentCodes.insert(0, code);
      }
      if (_recentCodes.length > _recentCodesLimit) {
        _recentCodes.removeRange(_recentCodesLimit, _recentCodes.length);
      }
    });

    _schedulePersistRecentCodes();
  }

  Future<void> _loadRecentCodes() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_recentCodesKey) ?? const <String>[];
    if (!mounted) return;
    _prefs = prefs;
    if (stored.isEmpty) return;
    setState(() {
      _recentCodes
        ..clear()
        ..addAll(stored.take(_recentCodesLimit));
    });
  }

  Future<void> _persistRecentCodes() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.setStringList(
      _recentCodesKey,
      List<String>.from(_recentCodes.take(_recentCodesLimit)),
    );
  }

  void _schedulePersistRecentCodes() {
    _recentCodesDirty = true;
    _persistRecentCodesTimer?.cancel();
    _persistRecentCodesTimer = Timer(
      const Duration(milliseconds: 600),
      _flushRecentCodes,
    );
  }

  Future<void> _flushRecentCodes() async {
    if (!_recentCodesDirty) return;
    _recentCodesDirty = false;
    await _persistRecentCodes();
  }

  void _addConfirmedResult(ScanResult result) {
    final code = result.barcodeText.trim();
    if (code.isEmpty) return;
    _insertRecentCodes([code]);
    if (mounted) {
      showAppFeedbackBanner(
        context,
        'Se guardó correctamente.',
        tone: AppFeedbackTone.success,
      );
    }
  }

  Future<void> _showRecentCodes() async {
    if (_recentCodes.isEmpty) {
      if (mounted) {
        showAppFeedbackBanner(
          context,
          'Todavía no hay códigos guardados.',
          tone: AppFeedbackTone.info,
        );
      }
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          decoration: BoxDecoration(
            color: AppTheme.yellowField,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            border: Border.all(color: AppTheme.blue, width: 1.2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x331B305F),
                blurRadius: 18,
                offset: Offset(0, -6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.list_alt_rounded,
                    color: AppTheme.blue,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Últimos códigos escaneados',
                      style: TextStyle(
                        color: AppTheme.blue,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x66FFFFFF),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0x661B305F)),
                    ),
                    child: Text(
                      '${_recentCodes.length}',
                      style: const TextStyle(
                        color: AppTheme.blue,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Toca un código para copiarlo.',
                style: TextStyle(
                  color: AppTheme.blueMid,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _recentCodes.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final code = _recentCodes[index];
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: code));
                          Navigator.of(context).pop();
                          showAppFeedbackBanner(
                            context,
                            'Código copiado.',
                            tone: AppFeedbackTone.info,
                          );
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Ink(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xCCFFF7E7),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0x661B305F)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFE9A8),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0x801B305F),
                                  ),
                                ),
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    color: AppTheme.blue,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  code,
                                  style: const TextStyle(
                                    color: AppTheme.blue,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.copy_rounded,
                                color: AppTheme.blue,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cerrar'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isBatchPackageLookup
              ? 'Buscar paquetes'
              : _isPackageLookupMode
              ? 'Buscar paquete'
              : 'Clasificaciones',
        ),
        backgroundColor: AppTheme.yellow,
        foregroundColor: AppTheme.blue,
        actions: [
          if (_isBatchPackageLookup && _collectedPackageCodes.isNotEmpty)
            IconButton(
              tooltip: 'Terminar seleccion',
              onPressed: _finishBatchPackageLookup,
              icon: const Icon(Icons.done_all_rounded),
            ),
          TorchActionButton(controller: widget.controller),
        ],
      ),
      drawer: _isPackageLookupMode
          ? null
          : ProfileDrawer(
              displayName: _displayName,
              email: widget.currentUser.email,
              rememberSession: _rememberSession,
              useBiometric: _useBiometric,
              biometricAvailable: _biometricAvailable,
              onRememberSessionChanged: _setRememberSession,
              onUseBiometricChanged: _setUseBiometric,
              onLogout: _logout,
            ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          widget.controller.updateScanViewportSize(constraints.biggest);
          return ScannerBody(
            controller: widget.controller,
            lineAnimation: _lineController,
            onScanFromCamera: _scanFromCameraAndShowModal,
            onScanFromGallery: _scanFromGalleryWithCrop,
            onShowRecentCodes: _isPackageLookupMode
                ? _showManualPackageCodeInput
                : _showRecentCodes,
            packageLookupMode: _isPackageLookupMode,
            packageRecognitionMode: _packageRecognitionMode,
            onPackageRecognitionModeChanged: _isPackageLookupMode
                ? _changePackageRecognitionMode
                : null,
            selectedPackageCount: _isBatchPackageLookup
                ? _collectedPackageCodes.length
                : 0,
            onReviewSelectedPackages:
                _isBatchPackageLookup && widget.onReviewPackageCodes != null
                ? _reviewBatchPackageSelection
                : null,
          );
        },
      ),
    );
  }
}

class _OcrCodeVerificationDialog extends StatefulWidget {
  const _OcrCodeVerificationDialog({
    required this.initialCode,
    required this.onDisposed,
  });

  final String initialCode;
  final VoidCallback onDisposed;

  @override
  State<_OcrCodeVerificationDialog> createState() =>
      _OcrCodeVerificationDialogState();
}

class _OcrCodeVerificationDialogState
    extends State<_OcrCodeVerificationDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialCode);
    _focusNode = FocusNode();
  }

  void _close([String? result]) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(result);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    widget.onDisposed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.yellowField,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.blue),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Verificar código detectado',
              style: TextStyle(
                color: AppTheme.blue,
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Si la lectura no es correcta, puedes editar el código antes de seleccionarlo.',
              style: TextStyle(
                color: AppTheme.blueMid,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                labelText: 'Codigo del paquete',
                prefixIcon: Icon(Icons.edit_rounded, color: AppTheme.blue),
              ),
              onSubmitted: (_) => _close(_controller.text),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _close,
                    child: const Text('Reintentar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _close(_controller.text),
                    child: const Text('Seleccionar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualPackageCodeDialog extends StatefulWidget {
  const _ManualPackageCodeDialog({required this.onDisposed});

  final VoidCallback onDisposed;

  @override
  State<_ManualPackageCodeDialog> createState() =>
      _ManualPackageCodeDialogState();
}

class _ManualPackageCodeDialogState extends State<_ManualPackageCodeDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focusNode.canRequestFocus) _focusNode.requestFocus();
    });
  }

  void _close([String? result]) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(result);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    widget.onDisposed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ingresar código'),
      content: TextField(
        controller: _controller,
        focusNode: _focusNode,
        textCapitalization: TextCapitalization.characters,
        textInputAction: TextInputAction.search,
        decoration: const InputDecoration(
          hintText: 'Codigo de paquete',
          prefixIcon: Icon(Icons.keyboard_alt_rounded),
        ),
        onSubmitted: (_) => _close(_controller.text),
      ),
      actions: [
        TextButton(onPressed: _close, child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => _close(_controller.text),
          child: const Text('Buscar'),
        ),
      ],
    );
  }
}
