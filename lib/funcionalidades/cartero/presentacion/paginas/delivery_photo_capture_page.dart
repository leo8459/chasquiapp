import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:image_picker/image_picker.dart';

import 'package:scan_agbc/nucleo/tema/app_theme.dart';
import 'package:scan_agbc/nucleo/utilidades/user_friendly_error_mapper.dart';
import 'package:scan_agbc/nucleo/componentes/app_cards.dart';
import 'package:scan_agbc/nucleo/componentes/app_page_scaffold.dart';

class DeliveryPhotoCaptureResult {
  const DeliveryPhotoCaptureResult({
    required this.bytes,
    required this.contentType,
    required this.fileExtension,
  });

  final Uint8List bytes;
  final String contentType;
  final String fileExtension;
}

class DeliveryPhotoCapturePage extends StatefulWidget {
  const DeliveryPhotoCapturePage({super.key});

  static Future<List<CameraDescription>> preloadCameraCatalog() {
    final existingFuture = _cameraCatalogFuture;
    if (existingFuture != null) {
      return existingFuture;
    }

    final future = availableCameras();
    _cameraCatalogFuture = future;
    return future.catchError((error) {
      if (identical(_cameraCatalogFuture, future)) {
        _cameraCatalogFuture = null;
      }
      throw error;
    });
  }

  static Future<List<CameraDescription>>? _cameraCatalogFuture;

  @override
  State<DeliveryPhotoCapturePage> createState() =>
      _DeliveryPhotoCapturePageState();
}

class _DeliveryPhotoCapturePageState extends State<DeliveryPhotoCapturePage>
    with SingleTickerProviderStateMixin {
  static const int _maxDeliveryPhotoBytes = 15 * 1024 * 1024;
  static const double _viewportAspectRatio = 0.78;
  static const double _documentAspectRatio = 0.70710678118;
  static const ResolutionPreset _captureResolution = ResolutionPreset.medium;

  CameraController? _cameraController;
  final ImagePicker _imagePicker = ImagePicker();
  late final AnimationController _pulseController;
  Uint8List? _previewImageBytes;
  final String _previewContentType = 'image/jpeg';
  final String _previewFileExtension = 'jpg';
  bool _initializingCamera = false;
  bool _capturing = false;
  bool _permissionDenied = false;
  String? _errorMessage;

  bool get _cameraReady =>
      _cameraController != null && _cameraController!.value.isInitialized;

  bool get _busy => _capturing || _initializingCamera;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    unawaited(_activateCamera());
  }

  @override
  void dispose() {
    _pulseController.dispose();
    final controller = _cameraController;
    _cameraController = null;
    unawaited(controller?.dispose());
    PaintingBinding.instance.imageCache.clearLiveImages();
    super.dispose();
  }

  Future<void> _activateCamera() async {
    if (_cameraReady || _initializingCamera) return;

    setState(() {
      _initializingCamera = true;
      _permissionDenied = false;
      _errorMessage = null;
    });

    try {
      await _initCamera();
    } finally {
      if (mounted) {
        setState(() {
          _initializingCamera = false;
        });
      }
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await DeliveryPhotoCapturePage.preloadCameraCatalog();
      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        backCamera,
        _captureResolution,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _permissionDenied = false;
        _errorMessage = null;
      });
      unawaited(_configureDocumentCapture(controller));
    } on CameraException catch (error) {
      if (!mounted) return;
      setState(() {
        _permissionDenied = error.code.toLowerCase().contains(
          'cameraaccessdenied',
        );
        _errorMessage = _permissionDenied
            ? 'Necesitamos permiso para usar la cámara. Actívalo en ajustes.'
            : 'No pudimos abrir la cámara. Intenta nuevamente.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = UserFriendlyErrorMapper.message(
          error,
          fallback: 'No pudimos abrir la cámara. Intenta nuevamente.',
        );
      });
    }
  }

  Future<void> _configureDocumentCapture(CameraController controller) async {
    try {
      await controller.setFlashMode(FlashMode.off);
    } catch (_) {}
    try {
      await controller.setFocusMode(FocusMode.auto);
    } catch (_) {}
    try {
      await controller.setExposureMode(ExposureMode.auto);
    } catch (_) {}
  }

  Future<void> _restartCamera() async {
    if (_previewImageBytes != null) {
      setState(() {
        _previewImageBytes = null;
        _errorMessage = null;
      });
      return;
    }

    final controller = _cameraController;
    _cameraController = null;
    if (mounted) {
      setState(() {
        _permissionDenied = false;
        _errorMessage = null;
      });
    }
    if (controller != null) {
      await controller.dispose();
    }
    if (!mounted) return;
    await _activateCamera();
  }

  Future<void> _capturePhoto() async {
    if (!_cameraReady || _capturing || _previewImageBytes != null) return;

    setState(() {
      _capturing = true;
    });

    String? tempImagePath;
    try {
      if (!mounted || !_cameraReady) return;
      final file = await _cameraController!.takePicture();
      tempImagePath = file.path;
      final bytes = await File(file.path).readAsBytes();
      if (!mounted) return;
      await _setPreviewImage(bytes);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = UserFriendlyErrorMapper.message(
          error,
          fallback: 'No pudimos tomar la foto. Intenta nuevamente.',
        );
      });
    } finally {
      if (tempImagePath != null) {
        unawaited(_deleteTemporaryCapture(tempImagePath));
      }
      if (mounted) {
        setState(() {
          _capturing = false;
        });
      }
    }
  }

  Future<void> _pickPhotoFromGallery() async {
    if (_busy) return;

    try {
      final file = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (!mounted || file == null) return;

      final bytes = await file.readAsBytes();
      if (!mounted) return;
      await _setPreviewImage(bytes);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = UserFriendlyErrorMapper.message(
          error,
          fallback: 'No pudimos abrir la galeria. Intenta nuevamente.',
        );
      });
    }
  }

  Future<void> _setPreviewImage(Uint8List bytes) async {
    if (!mounted) return;

    final originalFormat = _detectImageFormat(bytes);

    if (bytes.isEmpty) {
      setState(() {
        _previewImageBytes = null;
        _errorMessage = 'No pudimos leer la foto elegida. Prueba con otra.';
      });
      return;
    }

    if (originalFormat.contentType == 'application/octet-stream') {
      setState(() {
        _previewImageBytes = null;
        _errorMessage =
            'Ese formato de imagen no es compatible. Usa una foto JPG o PNG.';
      });
      return;
    }

    if (bytes.lengthInBytes > _maxDeliveryPhotoBytes) {
      setState(() {
        _previewImageBytes = null;
        _errorMessage =
            'La foto pesa demasiado para enviarla. Toma otra más cerca o usa una imagen más liviana.';
      });
      return;
    }

    Navigator.of(context).pop(
      DeliveryPhotoCaptureResult(
        bytes: bytes,
        contentType: originalFormat.contentType,
        fileExtension: originalFormat.fileExtension,
      ),
    );
  }

  _ImagePayloadFormat _detectImageFormat(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return const _ImagePayloadFormat(
        contentType: 'image/png',
        fileExtension: 'png',
      );
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return const _ImagePayloadFormat(
        contentType: 'image/jpeg',
        fileExtension: 'jpg',
      );
    }
    return const _ImagePayloadFormat(
      contentType: 'application/octet-stream',
      fileExtension: 'bin',
    );
  }

  Future<void> _deleteTemporaryCapture(String imagePath) async {
    try {
      final file = File(imagePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<void> _confirmPreviewPhoto() async {
    final previewImageBytes = _previewImageBytes;
    if (previewImageBytes == null) return;

    final action = await showDialog<_PhotoPreviewAction>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppTheme.yellowField,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: AppTheme.blue, width: 1.4),
          ),
          titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
          contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
          actionsPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          title: const Column(
            children: [
              Icon(Icons.check_circle_rounded, color: AppTheme.blue, size: 40),
              SizedBox(height: 10),
              Text(
                'La foto esta bien?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.blueDark,
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                  height: 1.1,
                ),
              ),
            ],
          ),
          content: const Text(
            'Confirma para guardar esta foto como evidencia del comprobante o repitela si no salio clara.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.blueDark,
              fontWeight: FontWeight.w700,
              fontSize: 16,
              height: 1.35,
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(
                      dialogContext,
                    ).pop(_PhotoPreviewAction.retry),
                    child: const Text('Repetir'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(
                      dialogContext,
                    ).pop(_PhotoPreviewAction.confirm),
                    child: const Text('Confirmar'),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    if (action == _PhotoPreviewAction.retry) {
      setState(() {
        _previewImageBytes = null;
      });
      return;
    }
    if (action == _PhotoPreviewAction.confirm) {
      Navigator.of(context).pop(
        DeliveryPhotoCaptureResult(
          bytes: previewImageBytes,
          contentType: _previewContentType,
          fileExtension: _previewFileExtension,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).viewPadding.bottom;

    return AppPageScaffold(
      title: 'Foto del comprobante',
      backgroundDecoration: const BoxDecoration(color: Colors.transparent),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _DeliveryBackgroundSurface(
            cameraController: _cameraController,
            cameraReady: _cameraReady,
            showPreviewImage: _previewImageBytes != null,
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final isTablet = constraints.maxWidth >= 600;
              final previewMaxWidth = isTablet ? 560.0 : 520.0;
              final trayMaxWidth = isTablet ? 580.0 : double.infinity;

              return Padding(
                padding: EdgeInsets.fromLTRB(12, 16, 12, 16 + safeBottom),
                child: Column(
                  children: [
                    if (isTablet) ...[
                      const AppSectionIntroCard(
                        title: 'Captura del comprobante',
                        subtitle:
                            'Toma una foto clara. Se guardará temporalmente hasta confirmar.',
                        icon: Icons.camera_alt_rounded,
                      ),
                      const SizedBox(height: 16),
                    ],
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (_busy || _previewImageBytes != null) {
                            return;
                          }
                          if (_cameraReady) {
                            _capturePhoto();
                            return;
                          }
                          _activateCamera();
                        },
                        onVerticalDragEnd: (details) {
                          if (_cameraReady ||
                              _initializingCamera ||
                              _previewImageBytes != null) {
                            return;
                          }
                          final velocity = details.primaryVelocity ?? 0;
                          if (velocity < -800) {
                            _activateCamera();
                          }
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: previewMaxWidth,
                            ),
                            child: AspectRatio(
                              aspectRatio: _viewportAspectRatio,
                              child: LayoutBuilder(
                                builder: (context, viewportConstraints) {
                                  final viewportSize =
                                      viewportConstraints.biggest;
                                  final cameraController = _cameraController;
                                  final visibleViewport =
                                      Offset.zero & viewportSize;
                                  final showLiveCameraSurface =
                                      cameraController != null &&
                                      cameraController.value.isInitialized &&
                                      _previewImageBytes == null;
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(24),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        if (_previewImageBytes != null)
                                          _DeliveryPreviewSurface(
                                            imageBytes: _previewImageBytes!,
                                          )
                                        else if (showLiveCameraSurface)
                                          _DeliveryCameraSurface(
                                            cameraController: cameraController,
                                          ),
                                        if (_cameraReady &&
                                            _previewImageBytes == null)
                                          _DocumentOverlay(
                                            animation: _pulseController,
                                            showAnimation:
                                                _cameraReady &&
                                                !_initializingCamera,
                                            previewRect: visibleViewport,
                                            documentAspectRatio:
                                                _documentAspectRatio,
                                          ),
                                        if (_errorMessage != null &&
                                            _previewImageBytes == null)
                                          _CameraMessageState(
                                            title: _permissionDenied
                                                ? 'Permiso requerido'
                                                : 'No pudimos abrir la cámara',
                                            message:
                                                _errorMessage ??
                                                'Intenta nuevamente en un momento.',
                                            loading: false,
                                          ),
                                        if (_previewImageBytes == null)
                                          AnimatedOpacity(
                                            duration: const Duration(
                                              milliseconds: 280,
                                            ),
                                            opacity:
                                                (!_cameraReady &&
                                                    !_initializingCamera &&
                                                    _errorMessage == null)
                                                ? 1
                                                : 0,
                                            child: const _DeliveryLogoOverlay(
                                              cameraReady: false,
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: trayMaxWidth),
                        child: AppActionTray(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _CameraActionButton(
                                icon: Icons.photo_library_rounded,
                                tooltip: 'Galeria',
                                onPressed: _busy ? null : _pickPhotoFromGallery,
                              ),
                              _CameraActionButton.primary(
                                icon: _previewImageBytes != null
                                    ? Icons.check_rounded
                                    : (_busy
                                          ? Icons.autorenew_rounded
                                          : Icons.camera_alt_rounded),
                                tooltip: _previewImageBytes != null
                                    ? 'Guardar foto'
                                    : (_busy
                                          ? 'Capturando'
                                          : (_cameraReady
                                                ? 'Tomar foto'
                                                : 'Activar cámara')),
                                onPressed: !_busy
                                    ? (_previewImageBytes != null
                                          ? _confirmPreviewPhoto
                                          : (_cameraReady
                                                ? _capturePhoto
                                                : _activateCamera))
                                    : null,
                              ),
                              _CameraActionButton(
                                icon: _previewImageBytes != null
                                    ? Icons.replay_rounded
                                    : Icons.refresh_rounded,
                                tooltip: _previewImageBytes != null
                                    ? 'Repetir'
                                    : 'Reiniciar',
                                onPressed: _busy ? null : _restartCamera,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DeliveryBackgroundSurface extends StatelessWidget {
  const _DeliveryBackgroundSurface({
    required this.cameraController,
    required this.cameraReady,
    required this.showPreviewImage,
  });

  final CameraController? cameraController;
  final bool cameraReady;
  final bool showPreviewImage;

  @override
  Widget build(BuildContext context) {
    final activeCameraController = cameraController;

    return DecoratedBox(
      decoration:
          cameraReady && !showPreviewImage && activeCameraController != null
          ? const BoxDecoration(color: AppTheme.blueDark)
          : const BoxDecoration(
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
      child: cameraReady && !showPreviewImage && activeCameraController != null
          ? LayoutBuilder(
              builder: (context, constraints) {
                final cameraRect = _buildCoverViewportRect(
                  constraints.biggest,
                  _cameraPreviewAspectRatio(activeCameraController),
                );

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fromRect(
                      rect: cameraRect,
                      child: CameraPreview(activeCameraController),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              AppTheme.yellowLight.withValues(alpha: 0.68),
                              AppTheme.orangeWarm.withValues(alpha: 0.68),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            )
          : const SizedBox.expand(),
    );
  }
}

class _DeliveryCameraSurface extends StatelessWidget {
  const _DeliveryCameraSurface({required this.cameraController});

  final CameraController cameraController;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cameraRect = _buildCoverViewportRect(
          constraints.biggest,
          _cameraPreviewAspectRatio(cameraController),
        );

        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            const ColoredBox(color: Colors.black),
            Positioned.fromRect(
              rect: cameraRect,
              child: CameraPreview(cameraController),
            ),
          ],
        );
      },
    );
  }
}

double _cameraPreviewAspectRatio(CameraController controller) {
  final rawAspectRatio = controller.value.aspectRatio;
  return rawAspectRatio > 1 ? 1 / rawAspectRatio : rawAspectRatio;
}

Rect _buildCoverViewportRect(Size containerSize, double contentAspectRatio) {
  final containerAspectRatio =
      containerSize.width / math.max(containerSize.height, 1);

  late final double contentWidth;
  late final double contentHeight;

  if (contentAspectRatio > containerAspectRatio) {
    contentHeight = containerSize.height;
    contentWidth = contentHeight * contentAspectRatio;
  } else {
    contentWidth = containerSize.width;
    contentHeight = contentWidth / contentAspectRatio;
  }

  final left = (containerSize.width - contentWidth) / 2;
  final top = (containerSize.height - contentHeight) / 2;
  return Rect.fromLTWH(left, top, contentWidth, contentHeight);
}

Rect _buildDocumentGuideRect(
  Rect previewRect, {
  required double documentAspectRatio,
}) {
  final horizontalPadding = math.max(5.0, previewRect.width * 0.012);
  final verticalPadding = math.max(6.0, previewRect.height * 0.012);
  final maxWidth = math.max(1.0, previewRect.width - (horizontalPadding * 2));
  final maxHeight = math.max(1.0, previewRect.height - (verticalPadding * 2));
  var width = maxWidth;
  var height = width / documentAspectRatio;

  if (height > maxHeight) {
    height = maxHeight;
    width = height * documentAspectRatio;
  }

  final left = previewRect.left + ((previewRect.width - width) / 2);
  final centeredTop = previewRect.top + ((previewRect.height - height) / 2);
  final top = centeredTop.clamp(
    previewRect.top + (verticalPadding * 0.2),
    previewRect.bottom - height - (verticalPadding * 0.2),
  );
  return Rect.fromLTWH(left, top.toDouble(), width, height);
}

class _DocumentOverlay extends StatelessWidget {
  const _DocumentOverlay({
    required this.animation,
    required this.showAnimation,
    required this.previewRect,
    required this.documentAspectRatio,
  });

  final Animation<double> animation;
  final bool showAnimation;
  final Rect previewRect;
  final double documentAspectRatio;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final roiRect = _buildDocumentGuideRect(
          previewRect,
          documentAspectRatio: documentAspectRatio,
        );
        final width = roiRect.width;
        const sidePadding = 16.0;
        final cornerSize = math.min(78.0, width * 0.24);

        return Stack(
          children: [
            Positioned.fromRect(
              rect: roiRect,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: AppTheme.overlayBorder,
                      width: 1.8,
                    ),
                    color: Colors.transparent,
                  ),
                ),
              ),
            ),
            _CornerMarker(
              left: roiRect.left,
              top: roiRect.top,
              isLeft: true,
              isTop: true,
              size: cornerSize,
            ),
            _CornerMarker(
              left: roiRect.right - cornerSize,
              top: roiRect.top,
              isLeft: false,
              isTop: true,
              size: cornerSize,
            ),
            _CornerMarker(
              left: roiRect.left,
              top: roiRect.bottom - cornerSize,
              isLeft: true,
              isTop: false,
              size: cornerSize,
            ),
            _CornerMarker(
              left: roiRect.right - cornerSize,
              top: roiRect.bottom - cornerSize,
              isLeft: false,
              isTop: false,
              size: cornerSize,
            ),
            Positioned(
              left: roiRect.left + sidePadding,
              right: (constraints.maxWidth - roiRect.right) + sidePadding,
              bottom: roiRect.bottom - 34,
              child: const Text(
                'Centra la evidencia dentro del marco',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xEAFDECC0),
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                ),
              ),
            ),
            if (showAnimation)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: animation,
                  builder: (context, _) {
                    final scanY =
                        roiRect.top + (roiRect.height - 2) * animation.value;
                    return Stack(
                      children: [
                        Positioned(
                          left: roiRect.left + 12,
                          top: scanY,
                          width: roiRect.width - 24,
                          height: 2,
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Color(0x00F5BD28),
                                  AppTheme.orangeWarm,
                                  Color(0x00F5BD28),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DeliveryPreviewSurface extends StatelessWidget {
  const _DeliveryPreviewSurface({required this.imageBytes});

  final Uint8List imageBytes;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x221B305F),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: const Color(0xFFF8F8F7)),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Image.memory(
                  imageBytes,
                  filterQuality: FilterQuality.medium,
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                ),
              ),
              Positioned(
                top: 14,
                left: 14,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xE6142A54),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.document_scanner_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Foto común',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImagePayloadFormat {
  const _ImagePayloadFormat({
    required this.contentType,
    required this.fileExtension,
  });

  final String contentType;
  final String fileExtension;
}

enum _PhotoPreviewAction { retry, confirm }

class _DeliveryLogoOverlay extends StatelessWidget {
  const _DeliveryLogoOverlay({required this.cameraReady});

  final bool cameraReady;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          const topPadding = 72.0;
          const logoHeight = 140.0;
          final idleTop = (constraints.maxHeight - logoHeight) * 0.42;
          final activeTop = topPadding;
          final targetTop = cameraReady ? activeTop : idleTop;
          final maxTop = constraints.maxHeight - logoHeight;

          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                left: 0,
                right: 0,
                top: targetTop.clamp(0.0, maxTop),
                child: Center(
                  child: Image.asset(
                    'assets/images/logo.png',
                    height: logoHeight,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CameraMessageState extends StatelessWidget {
  const _CameraMessageState({
    required this.title,
    required this.message,
    required this.loading,
  });

  final String title;
  final String message;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.yellowSoft,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0x661B305F)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const CircularProgressIndicator(color: AppTheme.blue)
              else
                const Icon(
                  Icons.camera_alt_rounded,
                  color: AppTheme.blue,
                  size: 34,
                ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.blue,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.blueDark,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CornerMarker extends StatelessWidget {
  const _CornerMarker({
    required this.left,
    required this.top,
    required this.isLeft,
    required this.isTop,
    required this.size,
  });

  final double left;
  final double top;
  final bool isLeft;
  final bool isTop;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: SizedBox(
          width: size,
          height: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                left: isLeft
                    ? const BorderSide(color: AppTheme.yellow, width: 4)
                    : BorderSide.none,
                right: !isLeft
                    ? const BorderSide(color: AppTheme.yellow, width: 4)
                    : BorderSide.none,
                top: isTop
                    ? const BorderSide(color: AppTheme.yellow, width: 4)
                    : BorderSide.none,
                bottom: !isTop
                    ? const BorderSide(color: AppTheme.yellow, width: 4)
                    : BorderSide.none,
              ),
              borderRadius: BorderRadius.only(
                topLeft: isLeft && isTop
                    ? const Radius.circular(24)
                    : Radius.zero,
                topRight: !isLeft && isTop
                    ? const Radius.circular(24)
                    : Radius.zero,
                bottomLeft: isLeft && !isTop
                    ? const Radius.circular(24)
                    : Radius.zero,
                bottomRight: !isLeft && !isTop
                    ? const Radius.circular(24)
                    : Radius.zero,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraActionButton extends StatelessWidget {
  const _CameraActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  }) : _primary = false;

  const _CameraActionButton.primary({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  }) : _primary = true;

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool _primary;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;
    final buttonStyle = OutlinedButton.styleFrom(
      foregroundColor: AppTheme.blueDark,
      disabledForegroundColor: const Color(0x99627BA8),
      side: BorderSide(
        color: AppTheme.strongBorder,
        width: _primary ? 2.1 : 1.5,
      ),
      backgroundColor: _primary
          ? AppTheme.actionYellowStrong
          : AppTheme.actionSurfaceSoft,
      disabledBackgroundColor: const Color(0x99EFE5CB),
      shape: const CircleBorder(),
      padding: EdgeInsets.all(_primary ? 27 : 16),
    );

    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: isEnabled
              ? [
                  BoxShadow(
                    color: _primary
                        ? AppTheme.strongShadow
                        : AppTheme.softShadow,
                    blurRadius: _primary ? 10 : 7,
                    offset: const Offset(0, 4),
                  ),
                ]
              : const [],
        ),
        child: OutlinedButton(
          onPressed: onPressed,
          style: buttonStyle,
          child: Icon(icon, size: _primary ? 32 : 24),
        ),
      ),
    );
  }
}
