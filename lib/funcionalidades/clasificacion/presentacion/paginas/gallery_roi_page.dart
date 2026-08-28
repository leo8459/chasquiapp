import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:scan_agbc/nucleo/tema/app_theme.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/presentacion/controladores/scanner_controller.dart';

enum _CropTarget { barcode, ocr }

enum _SelectionDragMode {
  none,
  create,
  move,
  resizeTopLeft,
  resizeTopRight,
  resizeBottomLeft,
  resizeBottomRight,
}

class GalleryRoiPage extends StatefulWidget {
  const GalleryRoiPage({
    super.key,
    required this.imagePath,
    required this.controller,
    this.barcodeOnly = false,
  });

  final String imagePath;
  final ScannerController controller;
  final bool barcodeOnly;

  @override
  State<GalleryRoiPage> createState() => _GalleryRoiPageState();
}

class _GalleryRoiPageState extends State<GalleryRoiPage> {
  late Future<Size> _imageSizeFuture;
  late String _currentImagePath;
  final ImagePicker _imagePicker = ImagePicker();
  Rect? _barcodeSelection;
  Rect? _ocrSelection;
  Rect? _draftSelection;
  Rect? _dragBaseRect;
  Offset? _dragStart;
  Size _canvasSize = Size.zero;
  Size? _imageSize;
  _CropTarget _currentTarget = _CropTarget.barcode;
  _SelectionDragMode _dragMode = _SelectionDragMode.none;
  bool _isProcessing = false;

  static const double _minSelectionSide = 24;
  static const double _cornerHitRadius = 22;
  static const Object _unset = Object();

  @override
  void initState() {
    super.initState();
    _currentImagePath = widget.imagePath;
    _imageSizeFuture = _readImageSize(_currentImagePath);
  }

  Future<Size> _readImageSize(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        return Size(image.width.toDouble(), image.height.toDouble());
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  Offset _clampPoint(Offset point) {
    return Offset(
      point.dx.clamp(0.0, _canvasSize.width),
      point.dy.clamp(0.0, _canvasSize.height),
    );
  }

  Rect _normalizedRect(Rect rect) {
    if (_canvasSize.width <= 0 || _canvasSize.height <= 0) {
      return const Rect.fromLTWH(0, 0, 1, 1);
    }
    final left = (rect.left / _canvasSize.width).clamp(0.0, 1.0);
    final top = (rect.top / _canvasSize.height).clamp(0.0, 1.0);
    final right = (rect.right / _canvasSize.width).clamp(0.0, 1.0);
    final bottom = (rect.bottom / _canvasSize.height).clamp(0.0, 1.0);
    return Rect.fromLTRB(left, top, right, bottom);
  }

  Rect? get _activeSelection =>
      _currentTarget == _CropTarget.barcode ? _barcodeSelection : _ocrSelection;

  bool get _canConfirm => widget.barcodeOnly
      ? _barcodeSelection != null
      : _barcodeSelection != null && _ocrSelection != null;

  void _setActiveSelection(Rect? rect) {
    final currentSelection = _activeSelection;
    if (currentSelection == rect) return;
    setState(() {
      if (_currentTarget == _CropTarget.barcode) {
        _barcodeSelection = rect;
      } else {
        _ocrSelection = rect;
      }
    });
  }

  _CropTarget? _targetAtPoint(Offset point) {
    final activeSelection = _activeSelection;
    if (activeSelection != null && activeSelection.contains(point)) {
      return _currentTarget;
    }

    if (widget.barcodeOnly) return null;

    final otherTarget = _currentTarget == _CropTarget.barcode
        ? _CropTarget.ocr
        : _CropTarget.barcode;
    final otherSelection = otherTarget == _CropTarget.barcode
        ? _barcodeSelection
        : _ocrSelection;
    if (otherSelection != null && otherSelection.contains(point)) {
      return otherTarget;
    }
    return null;
  }

  void _setCurrentTarget(_CropTarget target) {
    if (_currentTarget == target) return;
    setState(() {
      _currentTarget = target;
    });
  }

  bool _isDragStateCleared() {
    return _draftSelection == null &&
        _dragStart == null &&
        _dragBaseRect == null &&
        _dragMode == _SelectionDragMode.none;
  }

  void _setDragState({
    Object? currentTarget = _unset,
    Object? dragStart = _unset,
    Object? dragBaseRect = _unset,
    Object? dragMode = _unset,
    Object? draftSelection = _unset,
  }) {
    final nextTarget = currentTarget == _unset
        ? _currentTarget
        : currentTarget as _CropTarget;
    final nextDragStart = dragStart == _unset
        ? _dragStart
        : dragStart as Offset?;
    final nextDragBase = dragBaseRect == _unset
        ? _dragBaseRect
        : dragBaseRect as Rect?;
    final nextDragMode = dragMode == _unset
        ? _dragMode
        : dragMode as _SelectionDragMode;
    final nextDraft = draftSelection == _unset
        ? _draftSelection
        : draftSelection as Rect?;

    if (_currentTarget == nextTarget &&
        _dragStart == nextDragStart &&
        _dragBaseRect == nextDragBase &&
        _dragMode == nextDragMode &&
        _draftSelection == nextDraft) {
      return;
    }

    setState(() {
      _currentTarget = nextTarget;
      _dragStart = nextDragStart;
      _dragBaseRect = nextDragBase;
      _dragMode = nextDragMode;
      _draftSelection = nextDraft;
    });
  }

  _SelectionDragMode _resolveDragMode(Rect rect, Offset point) {
    if ((point - rect.topLeft).distance <= _cornerHitRadius) {
      return _SelectionDragMode.resizeTopLeft;
    }
    if ((point - rect.topRight).distance <= _cornerHitRadius) {
      return _SelectionDragMode.resizeTopRight;
    }
    if ((point - rect.bottomLeft).distance <= _cornerHitRadius) {
      return _SelectionDragMode.resizeBottomLeft;
    }
    if ((point - rect.bottomRight).distance <= _cornerHitRadius) {
      return _SelectionDragMode.resizeBottomRight;
    }
    if (rect.contains(point)) return _SelectionDragMode.move;
    return _SelectionDragMode.none;
  }

  Rect _clampRectToCanvas(Rect rect) {
    final left = rect.left.clamp(0.0, _canvasSize.width);
    final top = rect.top.clamp(0.0, _canvasSize.height);
    final right = rect.right.clamp(0.0, _canvasSize.width);
    final bottom = rect.bottom.clamp(0.0, _canvasSize.height);
    return Rect.fromLTRB(left, top, right, bottom);
  }

  Rect? _buildUpdatedDraft(Offset currentPoint) {
    final start = _dragStart;
    if (start == null) return null;

    switch (_dragMode) {
      case _SelectionDragMode.create:
        return Rect.fromPoints(start, currentPoint);
      case _SelectionDragMode.move:
        final base = _dragBaseRect;
        if (base == null) return null;
        final delta = currentPoint - start;
        final dx = delta.dx.clamp(-base.left, _canvasSize.width - base.right);
        final dy = delta.dy.clamp(-base.top, _canvasSize.height - base.bottom);
        return base.shift(Offset(dx, dy));
      case _SelectionDragMode.resizeTopLeft:
      case _SelectionDragMode.resizeTopRight:
      case _SelectionDragMode.resizeBottomLeft:
      case _SelectionDragMode.resizeBottomRight:
        final base = _dragBaseRect;
        if (base == null) return null;
        final anchor = switch (_dragMode) {
          _SelectionDragMode.resizeTopLeft => base.bottomRight,
          _SelectionDragMode.resizeTopRight => base.bottomLeft,
          _SelectionDragMode.resizeBottomLeft => base.topRight,
          _SelectionDragMode.resizeBottomRight => base.topLeft,
          _ => base.topLeft,
        };
        return Rect.fromPoints(anchor, currentPoint);
      case _SelectionDragMode.none:
        return null;
    }
  }

  Future<void> _nextStepOrConfirm() async {
    if (!widget.barcodeOnly && _currentTarget == _CropTarget.barcode) {
      if (_barcodeSelection == null) return;
      setState(() {
        _currentTarget = _CropTarget.ocr;
      });
      return;
    }
    if (!_canConfirm || _isProcessing) return;

    final barcodeRoi = _normalizedRect(_barcodeSelection!);
    final ocrRoi = widget.barcodeOnly
        ? barcodeRoi
        : _normalizedRect(_ocrSelection!);

    setState(() {
      _isProcessing = true;
    });

    final resolvedImageSize = _imageSize ?? await _imageSizeFuture;
    await widget.controller.scanFichaFromImagePath(
      _currentImagePath,
      normalizedBarcodeRoi: barcodeRoi,
      normalizedOcrRoi: ocrRoi,
      imageSize: resolvedImageSize,
    );
    if (!mounted) return;

    setState(() {
      _isProcessing = false;
    });

    if (!widget.controller.hasDetectedContent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se detectó contenido. Ajusta recortes e intenta.'),
        ),
      );
      return;
    }

    if (widget.barcodeOnly) {
      Navigator.of(context).pop(true);
      return;
    }

    final continueToConfirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: AppTheme.yellowField,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppTheme.blue),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Escaneo completado',
                  style: TextStyle(
                    color: AppTheme.blue,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 10),
                _ScanSummaryBox(
                  title: 'Codigo de barras',
                  value: widget.controller.barcodeResult,
                ),
                const SizedBox(height: 8),
                _ScanSummaryBox(
                  title: 'Texto OCR',
                  value: widget.controller.ocrResult,
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('Cerrar'),
                    ),
                    const SizedBox(width: 6),
                    FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.blue,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Continuar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (continueToConfirm == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _pickAnotherImage() async {
    if (_isProcessing) return;
    final image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;

    setState(() {
      _currentImagePath = image.path;
      _imageSizeFuture = _readImageSize(_currentImagePath);
      _barcodeSelection = null;
      _ocrSelection = null;
      _draftSelection = null;
      _dragBaseRect = null;
      _dragStart = null;
      _dragMode = _SelectionDragMode.none;
      _currentTarget = _CropTarget.barcode;
      _canvasSize = Size.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeTitle = widget.barcodeOnly
        ? 'Paso 1: marca el área del código de barras'
        : _currentTarget == _CropTarget.barcode
        ? 'Paso 1: marca el área del código de barras'
        : 'Paso 2: marca el area del texto OCR';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recortes de escaneo'),
        backgroundColor: AppTheme.yellow,
        foregroundColor: AppTheme.blue,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFFFF), AppTheme.orangeWarm],
          ),
        ),
        child: FutureBuilder<Size>(
          future: _imageSizeFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const Center(
                child: Text('No se pudo cargar la imagen seleccionada.'),
              );
            }

            final imageSize = snapshot.data!;
            _imageSize = imageSize;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Text(
                    activeTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.blue,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Dibuja arrastrando. Si ya existe un recorte, arrastra dentro para mover o desde esquinas para redimensionar.',
                    style: TextStyle(
                      color: AppTheme.blue,
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _TargetChip(
                          label: 'Barcode',
                          selected: _currentTarget == _CropTarget.barcode,
                          onTap: () => _setCurrentTarget(_CropTarget.barcode),
                        ),
                      ),
                      if (!widget.barcodeOnly) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: _TargetChip(
                            label: 'OCR',
                            selected: _currentTarget == _CropTarget.ocr,
                            onTap: () => _setCurrentTarget(_CropTarget.ocr),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: AspectRatio(
                        aspectRatio: imageSize.width / imageSize.height,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            _canvasSize = Size(
                              constraints.maxWidth,
                              constraints.maxHeight,
                            );

                            return GestureDetector(
                              onPanStart: (details) {
                                final start = _clampPoint(
                                  details.localPosition,
                                );
                                final touchedTarget = _targetAtPoint(start);
                                final nextTarget =
                                    touchedTarget ?? _currentTarget;
                                final currentSelection =
                                    nextTarget == _CropTarget.barcode
                                    ? _barcodeSelection
                                    : _ocrSelection;
                                final mode = currentSelection == null
                                    ? _SelectionDragMode.create
                                    : _resolveDragMode(currentSelection, start);
                                final effectiveMode =
                                    mode == _SelectionDragMode.none
                                    ? _SelectionDragMode.create
                                    : mode;
                                _setDragState(
                                  currentTarget: nextTarget,
                                  dragStart: start,
                                  dragBaseRect: currentSelection,
                                  dragMode: effectiveMode,
                                  draftSelection:
                                      effectiveMode == _SelectionDragMode.create
                                      ? Rect.fromPoints(start, start)
                                      : currentSelection,
                                );
                              },
                              onPanUpdate: (details) {
                                final current = _clampPoint(
                                  details.localPosition,
                                );
                                final candidate = _buildUpdatedDraft(current);
                                if (candidate == null) return;
                                final rect = _clampRectToCanvas(candidate);
                                if (rect == _draftSelection) return;
                                setState(() {
                                  _draftSelection = rect;
                                });
                              },
                              onPanEnd: (_) {
                                final rect = _draftSelection;
                                if (rect == null ||
                                    rect.width < _minSelectionSide ||
                                    rect.height < _minSelectionSide) {
                                  if (_isDragStateCleared()) return;
                                  _setDragState(
                                    draftSelection: null,
                                    dragStart: null,
                                    dragBaseRect: null,
                                    dragMode: _SelectionDragMode.none,
                                  );
                                  return;
                                }
                                setState(() {
                                  if (_currentTarget == _CropTarget.barcode) {
                                    _barcodeSelection = rect;
                                  } else {
                                    _ocrSelection = rect;
                                  }
                                  _draftSelection = null;
                                  _dragStart = null;
                                  _dragBaseRect = null;
                                  _dragMode = _SelectionDragMode.none;
                                });
                              },
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.file(
                                      File(_currentImagePath),
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                  CustomPaint(
                                    painter: _DualSelectionPainter(
                                      barcodeSelection: _barcodeSelection,
                                      ocrSelection: _ocrSelection,
                                      activeTarget: _currentTarget,
                                      draftSelection: _draftSelection,
                                      showHandles:
                                          _dragMode !=
                                          _SelectionDragMode.create,
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Tooltip(
                          message: 'Cambiar imagen',
                          child: OutlinedButton.icon(
                            onPressed: _isProcessing ? null : _pickAnotherImage,
                            icon: const Icon(
                              Icons.swap_horiz_rounded,
                              size: 18,
                            ),
                            label: const Text('Imagen'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 46),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Tooltip(
                          message: 'Limpiar recorte activo',
                          child: OutlinedButton.icon(
                            onPressed: _activeSelection == null
                                ? null
                                : () => _setActiveSelection(null),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                            ),
                            label: const Text('Borrar'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 46),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _isProcessing
                              ? null
                              : (_currentTarget == _CropTarget.barcode &&
                                        _barcodeSelection == null) ||
                                    (!widget.barcodeOnly &&
                                        _currentTarget == _CropTarget.ocr &&
                                        !_canConfirm)
                              ? null
                              : _nextStepOrConfirm,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.yellow,
                            foregroundColor: AppTheme.blue,
                            minimumSize: const Size(0, 46),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                          ),
                          icon: Icon(
                            widget.barcodeOnly
                                ? Icons.check_circle_outline_rounded
                                : _currentTarget == _CropTarget.barcode
                                ? Icons.navigate_next_rounded
                                : Icons.check_circle_outline_rounded,
                            size: 18,
                          ),
                          label: Text(
                            _isProcessing
                                ? 'Procesando...'
                                : widget.barcodeOnly
                                ? 'Confirmar'
                                : _currentTarget == _CropTarget.barcode
                                ? 'Continuar'
                                : 'Confirmar',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DualSelectionPainter extends CustomPainter {
  const _DualSelectionPainter({
    required this.barcodeSelection,
    required this.ocrSelection,
    required this.activeTarget,
    required this.draftSelection,
    required this.showHandles,
  });

  final Rect? barcodeSelection;
  final Rect? ocrSelection;
  final _CropTarget activeTarget;
  final Rect? draftSelection;
  final bool showHandles;

  @override
  void paint(Canvas canvas, Size size) {
    final activeRect =
        draftSelection ??
        (activeTarget == _CropTarget.barcode ? barcodeSelection : ocrSelection);
    if (activeRect != null) {
      final shadePaint = Paint()..color = const Color(0x5A000000);
      final clearPaint = Paint()..blendMode = BlendMode.clear;
      canvas.saveLayer(Offset.zero & size, Paint());
      canvas.drawRect(Offset.zero & size, shadePaint);
      canvas.drawRect(activeRect, clearPaint);
      canvas.restore();
    }

    final barcodeOuterPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2
      ..color = AppTheme.blue;
    final barcodeInnerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..color = AppTheme.successGreen;
    if (barcodeSelection != null) {
      canvas.drawRect(barcodeSelection!, barcodeOuterPaint);
      canvas.drawRect(barcodeSelection!, barcodeInnerPaint);
    }

    final ocrOuterPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2
      ..color = AppTheme.blue;
    final ocrInnerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..color = AppTheme.warningYellow;
    if (ocrSelection != null) {
      canvas.drawRect(ocrSelection!, ocrOuterPaint);
      canvas.drawRect(ocrSelection!, ocrInnerPaint);
    }

    if (draftSelection != null) {
      final draftOuterPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.6
        ..color = AppTheme.blue;
      final draftInnerPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..color = activeTarget == _CropTarget.barcode
            ? AppTheme.successGreen
            : AppTheme.warningYellow;
      canvas.drawRect(draftSelection!, draftOuterPaint);
      canvas.drawRect(draftSelection!, draftInnerPaint);
    }

    final handleRect =
        draftSelection ??
        (activeTarget == _CropTarget.barcode ? barcodeSelection : ocrSelection);
    if (showHandles && handleRect != null) {
      final handleStroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppTheme.blue;
      final handleFill = Paint()..color = const Color(0xFFFBE19A);
      const handleRadius = 6.0;
      final corners = [
        handleRect.topLeft,
        handleRect.topRight,
        handleRect.bottomLeft,
        handleRect.bottomRight,
      ];
      for (final corner in corners) {
        canvas.drawCircle(corner, handleRadius, handleFill);
        canvas.drawCircle(corner, handleRadius, handleStroke);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DualSelectionPainter oldDelegate) {
    return oldDelegate.barcodeSelection != barcodeSelection ||
        oldDelegate.ocrSelection != ocrSelection ||
        oldDelegate.activeTarget != activeTarget ||
        oldDelegate.draftSelection != draftSelection ||
        oldDelegate.showHandles != showHandles;
  }
}

class _ScanSummaryBox extends StatelessWidget {
  const _ScanSummaryBox({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.yellowSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.blue.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.blue,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.trim().isEmpty ? 'Sin detectar' : value,
            style: const TextStyle(color: AppTheme.blue, fontSize: 13),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _TargetChip extends StatelessWidget {
  const _TargetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isBarcode = label == 'Barcode';
    final activeColor = isBarcode
        ? const Color(0xFF7CFF4F)
        : AppTheme.warningYellow;
    final bgColor = selected ? activeColor : AppTheme.yellowField;
    final textColor = AppTheme.blue;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: bgColor,
          border: Border.all(color: AppTheme.blue, width: selected ? 1.8 : 1.3),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? const Color(0x331B305F)
                  : const Color(0x221B305F),
              blurRadius: selected ? 12 : 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isBarcode
                    ? Icons.qr_code_2_rounded
                    : Icons.text_snippet_rounded,
                size: 18.5,
                color: textColor,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  letterSpacing: 0.35,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
