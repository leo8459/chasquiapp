import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:scan_agbc/nucleo/tema/app_theme.dart';
import 'package:scan_agbc/nucleo/utilidades/user_friendly_error_mapper.dart';
import 'package:scan_agbc/nucleo/componentes/app_cards.dart';
import 'package:scan_agbc/nucleo/componentes/app_feedback_banner.dart';
import 'package:scan_agbc/nucleo/componentes/app_page_scaffold.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/assigned_package_summary.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/package_tracking_result.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/repositorios/package_tracking_repository.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/utilidades/delivery_recipient_name_validator.dart';
import 'package:scan_agbc/funcionalidades/cartero/presentacion/paginas/delivery_evidence_preview_page.dart';
import 'package:scan_agbc/funcionalidades/cartero/presentacion/paginas/delivery_photo_capture_page.dart';
import 'package:scan_agbc/funcionalidades/cartero/presentacion/paginas/delivery_signature_capture_page.dart';
import 'package:scan_agbc/funcionalidades/cartero/presentacion/componentes/package_max_attempts_alert.dart';
import 'package:scan_agbc/funcionalidades/seguimiento/presentacion/componentes/package_tracking_result_card.dart';

class AssignedPackageDetailPage extends StatefulWidget {
  const AssignedPackageDetailPage({
    super.key,
    required this.assignment,
    required this.repository,
    required this.userId,
  });

  final AssignedPackageSummary assignment;
  final PackageTrackingRepository repository;
  final int userId;

  @override
  State<AssignedPackageDetailPage> createState() =>
      _AssignedPackageDetailPageState();
}

class _AssignedPackageDetailPageState extends State<AssignedPackageDetailPage> {
  late final Future<_AssignmentDetailViewData> _future;
  final TextEditingController _receivedByController = TextEditingController();
  final FocusNode _receivedByFocusNode = FocusNode();
  final TextEditingController _devolutionDescriptionController =
      TextEditingController();
  final FocusNode _devolutionDescriptionFocusNode = FocusNode();
  DeliveryPhotoCaptureResult? _deliveryPhoto;
  Uint8List? _deliverySignatureBytes;
  DeliveryPhotoCaptureResult? _devolutionPhoto;
  bool _savingDelivery = false;
  bool _savingDevolution = false;
  bool _missingLocationAlertShown = false;
  bool _devolutionMode = false;

  bool get _savingAnyAction => _savingDelivery || _savingDevolution;

  @override
  void initState() {
    super.initState();
    _future = _loadAssignmentDetails();
  }

  Future<_AssignmentDetailViewData> _loadAssignmentDetails() async {
    final result = await widget.repository.findByCode(widget.assignment.code);
    if (result == null) {
      throw StateError(
        'No se pudo recuperar el detalle del paquete ${widget.assignment.code}.',
      );
    }
    return _AssignmentDetailViewData(result: result);
  }

  @override
  void dispose() {
    _receivedByController.dispose();
    _receivedByFocusNode.dispose();
    _devolutionDescriptionController.dispose();
    _devolutionDescriptionFocusNode.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    _receivedByFocusNode.unfocus();
    _devolutionDescriptionFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
  }

  void _handleDeliveryModeChanged(bool value) {
    if (value == _devolutionMode) {
      return;
    }

    final moveFocusToDescription = value && _receivedByFocusNode.hasFocus;
    final moveFocusToReceivedBy =
        !value && _devolutionDescriptionFocusNode.hasFocus;

    setState(() {
      _devolutionMode = value;
    });

    if (!moveFocusToDescription && !moveFocusToReceivedBy) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final targetFocusNode = moveFocusToDescription
          ? _devolutionDescriptionFocusNode
          : _receivedByFocusNode;
      targetFocusNode.requestFocus();
      unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.show'));
    });
  }

  String _normalizeReceivedBy(String rawValue) {
    return DeliveryRecipientNameValidator.normalize(rawValue);
  }

  String? _validateReceivedBy(String rawValue) {
    return DeliveryRecipientNameValidator.validate(rawValue).errorMessage;
  }

  Future<void> _pasteReceivedBy() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final validation = DeliveryRecipientNameValidator.validate(
      clipboardData?.text ?? '',
    );
    final pastedValue = validation.normalizedValue;
    if (!validation.isValid) {
      if (!mounted) return;
      showAppFeedbackBanner(
        context,
        validation.errorMessage ??
            'No encontramos un nombre válido para pegar.',
        tone: AppFeedbackTone.info,
      );
      return;
    }

    _receivedByController.value = TextEditingValue(
      text: pastedValue,
      selection: TextSelection.collapsed(offset: pastedValue.length),
    );
    if (!mounted) return;
    showAppFeedbackBanner(
      context,
      'Nombre pegado en recibido por.',
      tone: AppFeedbackTone.info,
    );
  }

  Future<void> _captureDeliveryPhoto() async {
    if (_savingAnyAction) return;
    _dismissKeyboard();

    final photo = await Navigator.of(context).push<DeliveryPhotoCaptureResult>(
      MaterialPageRoute(builder: (_) => const DeliveryPhotoCapturePage()),
    );

    if (!mounted || photo == null) return;

    if (photo.bytes.isEmpty) {
      showAppFeedbackBanner(
        context,
        'No se pudo leer la foto capturada.',
        tone: AppFeedbackTone.error,
      );
      return;
    }

    setState(() {
      _deliveryPhoto = photo;
    });
    showAppFeedbackBanner(
      context,
      'Foto lista. Se guardará cuando confirmes la entrega.',
      tone: AppFeedbackTone.success,
    );
  }

  Future<void> _handleDeliveryPhotoCardTap() async {
    if (_savingAnyAction) return;
    _dismissKeyboard();

    final currentPhoto = _deliveryPhoto;
    if (currentPhoto == null) {
      await _captureDeliveryPhoto();
      return;
    }

    final decision = await Navigator.of(context)
        .push<DeliveryEvidencePreviewDecision>(
          MaterialPageRoute(
            builder: (_) => DeliveryEvidencePreviewPage(
              photo: currentPhoto,
              title: 'Foto de entrega',
              headline: 'Foto temporal lista',
              supportingText:
                  'Esta foto se guardará definitivamente cuando confirmes la entrega.',
              replaceActionLabel: 'Tomar otra',
              headerIcon: Icons.camera_alt_rounded,
            ),
          ),
        );
    if (!mounted) return;
    if (decision == DeliveryEvidencePreviewDecision.replace) {
      await _captureDeliveryPhoto();
    }
  }

  Future<void> _captureDeliverySignature() async {
    if (_savingAnyAction) return;
    _dismissKeyboard();

    final signatureBytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => const DeliverySignatureCapturePage()),
    );
    if (!mounted || signatureBytes == null) return;

    if (signatureBytes.isEmpty) {
      showAppFeedbackBanner(
        context,
        'No se pudo leer la firma capturada.',
        tone: AppFeedbackTone.error,
      );
      return;
    }

    setState(() {
      _deliverySignatureBytes = signatureBytes;
    });
    showAppFeedbackBanner(
      context,
      'Firma lista. Se guardará cuando confirmes la entrega.',
      tone: AppFeedbackTone.success,
    );
  }

  Future<void> _handleDeliverySignatureCardTap() async {
    if (_savingAnyAction) return;
    _dismissKeyboard();

    final currentSignature = _deliverySignatureBytes;
    if (currentSignature == null) {
      await _captureDeliverySignature();
      return;
    }

    final decision = await Navigator.of(context)
        .push<DeliveryEvidencePreviewDecision>(
          MaterialPageRoute(
            builder: (_) => DeliveryEvidencePreviewPage(
              photo: DeliveryPhotoCaptureResult(
                bytes: currentSignature,
                contentType: 'image/png',
                fileExtension: 'png',
              ),
              title: 'Firma de entrega',
              headline: 'Firma temporal lista',
              supportingText:
                  'Esta firma se guardará definitivamente cuando confirmes la entrega.',
              replaceActionLabel: 'Firmar otra',
              headerIcon: Icons.draw_rounded,
            ),
          ),
        );
    if (!mounted) return;
    if (decision == DeliveryEvidencePreviewDecision.replace) {
      await _captureDeliverySignature();
    }
  }

  Future<void> _confirmDelivery() async {
    if (_savingAnyAction) return;

    final receivedBy = _normalizeReceivedBy(_receivedByController.text);
    final receivedByError = _validateReceivedBy(receivedBy);
    if (receivedByError != null) {
      showAppFeedbackBanner(
        context,
        receivedByError,
        tone: AppFeedbackTone.error,
      );
      _receivedByFocusNode.requestFocus();
      return;
    }

    final deliveryPhoto = _deliveryPhoto;
    if (deliveryPhoto == null || deliveryPhoto.bytes.isEmpty) {
      showAppFeedbackBanner(
        context,
        'Debes registrar la foto de entrega.',
        tone: AppFeedbackTone.error,
      );
      return;
    }

    final signatureBytes = _deliverySignatureBytes;
    if (signatureBytes == null || signatureBytes.isEmpty) {
      showAppFeedbackBanner(
        context,
        'Debes registrar la firma de quien recibe el paquete.',
        tone: AppFeedbackTone.error,
      );
      return;
    }

    setState(() {
      _savingDelivery = true;
    });

    final evidenceTimestamp = DateTime.now().millisecondsSinceEpoch;
    var shouldRetrySave = false;
    try {
      await widget.repository.confirmAssignmentDelivered(
        assignmentId: widget.assignment.assignmentId,
        userId: widget.userId,
        receivedBy: receivedBy,
        deliveryPhotoBytes: deliveryPhoto.bytes,
        deliveryPhotoFileName: _buildDeliveryPhotoFileName(
          evidenceTimestamp,
          deliveryPhoto.fileExtension,
        ),
        deliveryPhotoContentType: deliveryPhoto.contentType,
        deliverySignatureBytes: signatureBytes,
        deliverySignatureFileName: _buildDeliverySignatureFileName(
          evidenceTimestamp,
        ),
      );
      if (!mounted) return;
      showAppFeedbackBanner(
        context,
        'Entrega guardada con foto y firma correctamente.',
        tone: AppFeedbackTone.success,
      );
      setState(() {
        _deliveryPhoto = null;
        _deliverySignatureBytes = null;
      });
      PaintingBinding.instance.imageCache.clearLiveImages();
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      final message = _mapError(error);
      showAppFeedbackBanner(context, message, tone: AppFeedbackTone.error);
      shouldRetrySave = await _showDeliverySaveErrorDialog(message);
    } finally {
      if (mounted) {
        setState(() {
          _savingDelivery = false;
        });
      }
    }

    if (shouldRetrySave && mounted) {
      await _confirmDelivery();
    }
  }

  Future<void> _captureDevolutionPhoto() async {
    if (_savingAnyAction) return;
    _dismissKeyboard();

    final photo = await Navigator.of(context).push<DeliveryPhotoCaptureResult>(
      MaterialPageRoute(builder: (_) => const DeliveryPhotoCapturePage()),
    );

    if (!mounted || photo == null) return;

    if (photo.bytes.isEmpty) {
      showAppFeedbackBanner(
        context,
        'No se pudo leer la foto de evidencia capturada.',
        tone: AppFeedbackTone.error,
      );
      return;
    }

    setState(() {
      _devolutionPhoto = photo;
    });
    showAppFeedbackBanner(
      context,
      'Foto de evidencia lista. Se guardará cuando registres la devolución.',
      tone: AppFeedbackTone.success,
    );
  }

  Future<void> _handleDevolutionPhotoCardTap() async {
    if (_savingAnyAction) return;
    _dismissKeyboard();

    final currentPhoto = _devolutionPhoto;
    if (currentPhoto == null) {
      await _captureDevolutionPhoto();
      return;
    }

    final decision = await Navigator.of(context)
        .push<DeliveryEvidencePreviewDecision>(
          MaterialPageRoute(
            builder: (_) => DeliveryEvidencePreviewPage(
              photo: currentPhoto,
              title: 'Foto de devolución',
              headline: 'Evidencia temporal lista',
              supportingText:
                  'Esta foto se guardará definitivamente cuando registres la devolución.',
              replaceActionLabel: 'Tomar otra',
              headerIcon: Icons.assignment_return_rounded,
            ),
          ),
        );
    if (!mounted) return;
    if (decision == DeliveryEvidencePreviewDecision.replace) {
      await _captureDevolutionPhoto();
    }
  }

  Future<void> _confirmDevolution() async {
    if (_savingAnyAction) return;

    final description = _devolutionDescriptionController.text.trim();
    if (description.length < 3) {
      showAppFeedbackBanner(
        context,
        'Describe brevemente lo ocurrido para registrar la devolución.',
        tone: AppFeedbackTone.error,
      );
      _devolutionDescriptionFocusNode.requestFocus();
      return;
    }

    final evidencePhoto = _devolutionPhoto;
    if (evidencePhoto == null || evidencePhoto.bytes.isEmpty) {
      showAppFeedbackBanner(
        context,
        'Debes registrar una foto de evidencia para la devolución.',
        tone: AppFeedbackTone.error,
      );
      return;
    }

    setState(() {
      _savingDevolution = true;
    });

    final evidenceTimestamp = DateTime.now().millisecondsSinceEpoch;
    var shouldRetrySave = false;
    try {
      final attemptCount = await widget.repository.registerAssignmentDevolution(
        assignmentId: widget.assignment.assignmentId,
        userId: widget.userId,
        description: description,
        evidencePhotoBytes: evidencePhoto.bytes,
        evidencePhotoFileName: _buildDevolutionPhotoFileName(
          evidenceTimestamp,
          evidencePhoto.fileExtension,
        ),
        evidencePhotoContentType: evidencePhoto.contentType,
      );
      if (!mounted) return;
      showAppFeedbackBanner(
        context,
        'Devolucion registrada con foto correctamente.',
        tone: AppFeedbackTone.success,
      );
      setState(() {
        _devolutionPhoto = null;
      });
      PaintingBinding.instance.imageCache.clearLiveImages();
      if (attemptCount >= 3) {
        await showPackageMaxAttemptsAlert(context);
        if (!mounted) return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      final message = _mapError(error);
      showAppFeedbackBanner(context, message, tone: AppFeedbackTone.error);
      shouldRetrySave = await _showDevolutionSaveErrorDialog(message);
    } finally {
      if (mounted) {
        setState(() {
          _savingDevolution = false;
        });
      }
    }

    if (shouldRetrySave && mounted) {
      await _confirmDevolution();
    }
  }

  Future<bool> _showDeliverySaveErrorDialog(String message) async {
    final retry = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('No pudimos guardar la entrega'),
          content: Text(
            '$message\n\nPuedes reintentar el envio sin volver a tomar la foto ni la firma.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cerrar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Reintentar'),
            ),
          ],
        );
      },
    );

    return retry == true;
  }

  Future<bool> _showDevolutionSaveErrorDialog(String message) async {
    final retry = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('No pudimos guardar la devolución'),
          content: Text(
            '$message\n\nPuedes reintentar el envio sin volver a tomar la foto.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cerrar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Reintentar'),
            ),
          ],
        );
      },
    );

    return retry == true;
  }

  String _buildDeliveryPhotoFileName(int timestamp, String fileExtension) {
    final normalizedExtension = fileExtension.trim().toLowerCase();
    final safeExtension = normalizedExtension.isEmpty
        ? 'jpg'
        : normalizedExtension;
    return 'confirmacion_${_sanitizedCode}_$timestamp.$safeExtension';
  }

  String _buildDeliverySignatureFileName(int timestamp) {
    return 'firma_${_sanitizedCode}_$timestamp.png';
  }

  String _buildDevolutionPhotoFileName(int timestamp, String fileExtension) {
    final normalizedExtension = fileExtension.trim().toLowerCase();
    final safeExtension = normalizedExtension.isEmpty
        ? 'jpg'
        : normalizedExtension;
    return 'devolucion_${_sanitizedCode}_$timestamp.$safeExtension';
  }

  String get _sanitizedCode {
    return widget.assignment.code.trim().toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]+'),
      '_',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: 'Detalle asignado',
      resizeToAvoidBottomInset: false,
      body: FutureBuilder<_AssignmentDetailViewData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.blue),
            );
          }

          if (snapshot.hasError) {
            return _AssignmentMessageState(
              title: 'No se pudo abrir la asignación',
              message: _mapError(snapshot.error),
            );
          }

          final data = snapshot.data!;
          if (data.result.hasLocationNote &&
              !data.result.hasHighlightLocation &&
              !_missingLocationAlertShown) {
            _missingLocationAlertShown = true;
            scheduleMissingPackageLocationAlert(
              context: context,
              result: data.result,
            );
          }

          return SingleChildScrollView(
            padding: AppTheme.pageCompactPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RepaintBoundary(
                  child: PackageTrackingResultCard(
                    result: data.result,
                    showCodeHeader: true,
                    showLocationArtwork: true,
                    panelBackgroundColor: Colors.white,
                    showWeight: false,
                    showAssignedCourier: false,
                    extraCompactItems: [
                      _WeightDisplayCard(weight: data.result.weight),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AppPanelCard(
                  padding: const EdgeInsets.all(18),
                  backgroundColor: _devolutionMode
                      ? AppTheme.actionYellowStrong
                      : AppTheme.blueDark,
                  borderRadius: AppTheme.radiusXLarge,
                  borderColor: AppTheme.blue,
                  boxShadow: const [
                    BoxShadow(
                      color: AppTheme.strongShadow,
                      blurRadius: 16,
                      offset: Offset(0, 8),
                    ),
                  ],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DeliveryModeToggle(
                        devolutionMode: _devolutionMode,
                        enabled: !_savingAnyAction,
                        onChanged: _handleDeliveryModeChanged,
                      ),
                      const SizedBox(height: 16),
                      _devolutionMode
                          ? const _DevolutionSectionHeader()
                          : const _DeliverySectionHeader(),
                      const SizedBox(height: 16),
                      Visibility(
                        visible: _devolutionMode,
                        maintainState: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _DescriptionCard(
                              controller: _devolutionDescriptionController,
                              focusNode: _devolutionDescriptionFocusNode,
                            ),
                            const SizedBox(height: 14),
                            _EvidenceCard(
                              title: 'Evidencia',
                              statusLabel: _devolutionPhoto == null
                                  ? 'Pendiente'
                                  : 'Hecho',
                              statusComplete: _devolutionPhoto != null,
                              icon: Icons.camera_alt_rounded,
                              helperText: _devolutionPhoto == null
                                  ? 'Toma la foto del intento fallido'
                                  : 'Toca para ver o reemplazar',
                              onPressed: _handleDevolutionPhotoCardTap,
                              emphasizedYellow: true,
                            ),
                            const SizedBox(height: 18),
                            FilledButton.icon(
                              onPressed: _savingAnyAction
                                  ? null
                                  : _confirmDevolution,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.blue,
                                foregroundColor: AppTheme.yellowField,
                                minimumSize: const Size.fromHeight(56),
                                side: const BorderSide(
                                  color: AppTheme.blueDark,
                                  width: AppTheme.borderWidth,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: AppTheme.radiusMedium,
                                ),
                              ),
                              icon: _savingDevolution
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: AppTheme.yellowField,
                                      ),
                                    )
                                  : const Icon(Icons.assignment_return_rounded),
                              label: Text(
                                _savingDevolution
                                    ? 'Guardando devolución...'
                                    : 'Registrar devolución',
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Guarda la descripción y la foto para dejar el intento registrado en DEVOLUCIÓN.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppTheme.blueDark,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Visibility(
                        visible: !_devolutionMode,
                        maintainState: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _ReceivedByCard(
                              controller: _receivedByController,
                              focusNode: _receivedByFocusNode,
                              onPasteReceivedBy: _pasteReceivedBy,
                            ),
                            const SizedBox(height: 14),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final showSideBySide =
                                    constraints.maxWidth >= 320;

                                final photoCard = _EvidenceCard(
                                  title: 'Foto',
                                  statusLabel: _deliveryPhoto == null
                                      ? 'Pendiente'
                                      : 'Hecho',
                                  statusComplete: _deliveryPhoto != null,
                                  icon: Icons.receipt_long_rounded,
                                  helperText: _deliveryPhoto == null
                                      ? 'Toma la foto de entrega'
                                      : 'Toca para ver o reemplazar',
                                  onPressed: _handleDeliveryPhotoCardTap,
                                );

                                final signatureCard = _EvidenceCard(
                                  title: 'Firma',
                                  statusLabel: _deliverySignatureBytes == null
                                      ? 'Pendiente'
                                      : 'Hecho',
                                  statusComplete:
                                      _deliverySignatureBytes != null,
                                  icon: Icons.draw_rounded,
                                  helperText: _deliverySignatureBytes == null
                                      ? 'Captura la firma'
                                      : 'Toca para ver o reemplazar',
                                  onPressed: _handleDeliverySignatureCardTap,
                                );

                                if (!showSideBySide) {
                                  return Column(
                                    children: [
                                      photoCard,
                                      const SizedBox(height: 14),
                                      signatureCard,
                                    ],
                                  );
                                }

                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: photoCard),
                                    const SizedBox(width: 14),
                                    Expanded(child: signatureCard),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 18),
                            const Divider(color: AppTheme.blueMid, height: 1),
                            const SizedBox(height: 18),
                            FilledButton.icon(
                              onPressed: _savingAnyAction
                                  ? null
                                  : _confirmDelivery,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.actionYellowStrong,
                                foregroundColor: AppTheme.blueDark,
                                minimumSize: const Size.fromHeight(58),
                                side: const BorderSide(
                                  color: AppTheme.blue,
                                  width: AppTheme.borderWidth,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: AppTheme.radiusMedium,
                                ),
                              ),
                              icon: _savingDelivery
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: AppTheme.blueDark,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.assignment_turned_in_rounded,
                                    ),
                              label: Text(
                                _savingDelivery
                                    ? 'Guardando entrega...'
                                    : 'Guardar entrega',
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Completa los datos y guarda.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppTheme.yellowSoft,
                                fontWeight: FontWeight.w600,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _mapError(Object? error) {
    return UserFriendlyErrorMapper.message(
      error,
      fallback:
          'No pudimos abrir la información del paquete. Intenta nuevamente.',
    );
  }
}

class _DeliverySectionHeader extends StatelessWidget {
  const _DeliverySectionHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _IntroBadge(),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Confirmar entrega',
                style: TextStyle(
                  color: AppTheme.yellowSurface,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Nombre, foto y firma.',
                style: TextStyle(
                  color: AppTheme.yellowSoft,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DeliveryModeToggle extends StatelessWidget {
  const _DeliveryModeToggle({
    required this.devolutionMode,
    required this.enabled,
    required this.onChanged,
  });

  final bool devolutionMode;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: devolutionMode ? AppTheme.yellowField : AppTheme.blue,
        borderRadius: AppTheme.radiusPill,
        border: Border.all(
          color: devolutionMode ? AppTheme.blue : AppTheme.yellowSoft,
          width: AppTheme.borderWidth,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeButton(
              label: 'Confirmar entrega',
              selected: !devolutionMode,
              enabled: enabled,
              selectedBackgroundColor: AppTheme.actionYellowStrong,
              selectedForegroundColor: AppTheme.blueDark,
              unselectedForegroundColor: devolutionMode
                  ? AppTheme.blue
                  : AppTheme.yellowSoft,
              onPressed: () => onChanged(false),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ModeButton(
              label: 'Registrar devolución',
              selected: devolutionMode,
              enabled: enabled,
              selectedBackgroundColor: AppTheme.blue,
              selectedForegroundColor: AppTheme.yellowField,
              unselectedForegroundColor: devolutionMode
                  ? AppTheme.blueDark
                  : Colors.white,
              onPressed: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.selectedBackgroundColor,
    required this.selectedForegroundColor,
    required this.unselectedForegroundColor,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final Color selectedBackgroundColor;
  final Color selectedForegroundColor;
  final Color unselectedForegroundColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      descendantsAreFocusable: false,
      child: FilledButton(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: selected
              ? selectedBackgroundColor
              : Colors.transparent,
          foregroundColor: selected
              ? selectedForegroundColor
              : unselectedForegroundColor,
          disabledBackgroundColor: selected
              ? selectedBackgroundColor.withValues(alpha: 0.7)
              : Colors.transparent,
          disabledForegroundColor: selected
              ? selectedForegroundColor.withValues(alpha: 0.8)
              : unselectedForegroundColor.withValues(alpha: 0.7),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: AppTheme.radiusPill),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 13,
            height: 1.15,
          ),
        ),
      ),
    );
  }
}

class _DevolutionSectionHeader extends StatelessWidget {
  const _DevolutionSectionHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _DevolutionBadge(),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Registrar devolución',
                style: TextStyle(
                  color: AppTheme.blueDark,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Descripcion y foto de evidencia.',
                style: TextStyle(
                  color: AppTheme.blueDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IntroBadge extends StatelessWidget {
  const _IntroBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.actionYellowStrong,
        borderRadius: AppTheme.radiusSmall,
        boxShadow: const [
          BoxShadow(
            color: AppTheme.softShadow,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: const Icon(
        Icons.fact_check_rounded,
        color: AppTheme.blueDark,
        size: 24,
      ),
    );
  }
}

class _DevolutionBadge extends StatelessWidget {
  const _DevolutionBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.blue,
        borderRadius: AppTheme.radiusSmall,
        boxShadow: const [
          BoxShadow(
            color: AppTheme.softShadow,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: const Icon(
        Icons.assignment_return_rounded,
        color: AppTheme.actionYellowStrong,
        size: 24,
      ),
    );
  }
}

class _WeightDisplayCard extends StatelessWidget {
  const _WeightDisplayCard({required this.weight});

  final String weight;

  @override
  Widget build(BuildContext context) {
    final displayWeight = weight.trim().isEmpty ? 'Sin peso' : weight;
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
              const Icon(Icons.scale_rounded, color: AppTheme.blue, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'PESO',
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
            displayWeight,
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

class _ReceivedByCard extends StatelessWidget {
  const _ReceivedByCard({
    required this.controller,
    required this.focusNode,
    required this.onPasteReceivedBy,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onPasteReceivedBy;

  @override
  Widget build(BuildContext context) {
    return AppSoftCard(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.person_pin_circle_rounded,
                color: AppTheme.blue,
                size: 22,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Recibido por',
                  style: TextStyle(
                    color: AppTheme.blue,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Escribe quien recibe el paquete.',
            style: TextStyle(
              color: AppTheme.blueDark,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            focusNode: focusNode,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            maxLength: 120,
            keyboardType: TextInputType.name,
            autocorrect: false,
            enableSuggestions: false,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            scrollPadding: EdgeInsets.zero,
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                RegExp(r"[A-Za-zÁÉÍÓÚÑáéíóúñ\s-]"),
              ),
            ],
            decoration: InputDecoration(
              fillColor: AppTheme.yellowLight,
              hintText: 'Ejemplo: Juan Perez',
              helperText:
                  'Solo letras. Cada parte debe tener al menos 2 letras.',
              enabledBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(18)),
                borderSide: BorderSide(
                  color: AppTheme.softBorder,
                  width: AppTheme.borderWidth,
                ),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(18)),
                borderSide: BorderSide(
                  color: AppTheme.confirmBlueDark,
                  width: 1.5,
                ),
              ),
              suffixIcon: IconButton(
                onPressed: onPasteReceivedBy,
                icon: const Icon(
                  Icons.content_paste_rounded,
                  color: AppTheme.blue,
                ),
                tooltip: 'Pegar',
              ),
              counterText: '',
            ),
          ),
        ],
      ),
    );
  }
}

class _DescriptionCard extends StatelessWidget {
  const _DescriptionCard({required this.controller, required this.focusNode});

  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return AppSoftCard(
      padding: const EdgeInsets.all(16),
      backgroundColor: AppTheme.yellowField,
      borderRadius: AppTheme.radiusLarge,
      borderColor: AppTheme.softBorder,
      boxShadow: const [
        BoxShadow(
          color: AppTheme.softShadow,
          blurRadius: 10,
          offset: Offset(0, 4),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.edit_note_rounded, color: AppTheme.blue, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Descripcion',
                  style: TextStyle(
                    color: AppTheme.blue,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Explica brevemente lo ocurrido en la visita.',
            style: TextStyle(
              color: AppTheme.blueDark,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            focusNode: focusNode,
            maxLength: 300,
            maxLines: 4,
            minLines: 3,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.sentences,
            autocorrect: false,
            enableSuggestions: false,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            scrollPadding: EdgeInsets.zero,
            decoration: const InputDecoration(
              fillColor: AppTheme.yellowLight,
              hintText:
                  'Ejemplo: No habia nadie en el domicilio y se dejo constancia fotografica.',
              helperText: 'Este texto se guardará en descripción.',
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(18)),
                borderSide: BorderSide(
                  color: AppTheme.softBorder,
                  width: AppTheme.borderWidth,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(18)),
                borderSide: BorderSide(color: AppTheme.blue, width: 1.5),
              ),
              counterText: '',
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard({
    required this.title,
    required this.statusLabel,
    required this.statusComplete,
    required this.icon,
    required this.helperText,
    required this.onPressed,
    this.emphasizedYellow = false,
  });

  final String title;
  final String statusLabel;
  final bool statusComplete;
  final IconData icon;
  final String helperText;
  final VoidCallback onPressed;
  final bool emphasizedYellow;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: AppTheme.radiusLarge,
        child: AppSoftCard(
          padding: const EdgeInsets.all(12),
          backgroundColor: emphasizedYellow
              ? (statusComplete ? AppTheme.yellowSoft : AppTheme.yellowSurface)
              : (statusComplete
                    ? AppTheme.yellowField
                    : AppTheme.yellowSurface),
          borderRadius: AppTheme.radiusLarge,
          borderColor: statusComplete
              ? AppTheme.blue
              : (emphasizedYellow ? AppTheme.softBorder : AppTheme.lightBorder),
          boxShadow: [
            BoxShadow(
              color: statusComplete
                  ? const Color(0x331B305F)
                  : AppTheme.softShadow,
              blurRadius: statusComplete ? 16 : 10,
              offset: const Offset(0, 6),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: statusComplete
                          ? AppTheme.blue
                          : (emphasizedYellow
                                ? AppTheme.yellowField
                                : AppTheme.actionSurfaceSoft),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: statusComplete
                            ? AppTheme.blue
                            : (emphasizedYellow
                                  ? AppTheme.softBorder
                                  : AppTheme.lightBorder),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: AppTheme.softShadow,
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(
                      icon,
                      color: statusComplete
                          ? AppTheme.actionYellowStrong
                          : AppTheme.blue,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: AppTheme.blueDark,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _EvidenceStatusChip(
                    label: statusLabel,
                    complete: statusComplete,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                helperText,
                style: const TextStyle(
                  color: AppTheme.blueDark,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EvidenceStatusChip extends StatelessWidget {
  const _EvidenceStatusChip({required this.label, required this.complete});

  final String label;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: complete ? AppTheme.blue : AppTheme.yellowLight,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: complete ? AppTheme.blue : AppTheme.softBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            complete ? Icons.check_circle_rounded : Icons.schedule_rounded,
            size: 14,
            color: complete ? AppTheme.actionYellowStrong : AppTheme.blueDark,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: complete ? AppTheme.yellowField : AppTheme.blueDark,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _AssignmentMessageState extends StatelessWidget {
  const _AssignmentMessageState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: AppStatusMessageCard(
          title: title,
          message: message,
          icon: Icons.error_outline_rounded,
          iconColor: AppTheme.errorRed,
        ),
      ),
    );
  }
}

class _AssignmentDetailViewData {
  const _AssignmentDetailViewData({required this.result});

  final PackageTrackingResult result;
}
