import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:scan_agbc/nucleo/tema/app_theme.dart';
import 'package:scan_agbc/nucleo/componentes/app_cards.dart';
import 'package:scan_agbc/nucleo/componentes/app_feedback_banner.dart';
import 'package:scan_agbc/nucleo/componentes/app_page_scaffold.dart';

class DeliverySignatureCapturePage extends StatefulWidget {
  const DeliverySignatureCapturePage({super.key});

  @override
  State<DeliverySignatureCapturePage> createState() =>
      _DeliverySignatureCapturePageState();
}

class _DeliverySignatureCapturePageState
    extends State<DeliverySignatureCapturePage> {
  static const int _minimumSignaturePointCount = 5;
  static const double _touchMinimumDistance = 1.5;
  static const double _stylusMinimumDistance = 0.8;

  final GlobalKey _signatureKey = GlobalKey();
  final ValueNotifier<int> _strokeRevision = ValueNotifier<int>(0);
  final List<List<Offset>> _strokes = <List<Offset>>[];

  int _strokePointCount = 0;
  bool _exporting = false;
  int? _activePointer;
  ui.PointerDeviceKind? _activePointerKind;
  DateTime? _lastStylusDetectedAt;
  Rect? _strokeExtents;

  bool get _hasSignature => _strokePointCount >= _minimumSignaturePointCount;

  bool get _stylusSessionActive {
    final lastStylusDetectedAt = _lastStylusDetectedAt;
    if (_isStylusKind(_activePointerKind)) {
      return true;
    }
    if (lastStylusDetectedAt == null) {
      return false;
    }
    return DateTime.now().difference(lastStylusDetectedAt) <
        const Duration(seconds: 2);
  }

  void _startStroke(PointerDownEvent event) {
    if (_exporting || _activePointer != null) return;
    if (!_supportsSignatureInput(event.kind)) return;
    if (!_allowsInputKind(event.kind)) return;

    final point = _localPointFor(event.position);
    if (point == null) return;

    final hadSignature = _hasSignature;
    final stylusWasActive = _stylusSessionActive;

    if (_isStylusKind(event.kind)) {
      _lastStylusDetectedAt = DateTime.now();
    }

    _activePointer = event.pointer;
    _activePointerKind = event.kind;
    final stroke = <Offset>[];
    _strokes.add(stroke);
    _appendPointToStroke(stroke, point);
    _notifyStrokePaint();
    _refreshUiIfNeeded(
      hadSignature: hadSignature,
      stylusWasActive: stylusWasActive,
    );
  }

  void _appendStroke(PointerMoveEvent event) {
    if (_activePointer != event.pointer || _strokes.isEmpty) return;

    final point = _localPointFor(event.position);
    if (point == null) return;

    final hadSignature = _hasSignature;
    final stylusWasActive = _stylusSessionActive;

    if (_isStylusKind(event.kind)) {
      _lastStylusDetectedAt = DateTime.now();
    }

    final currentStroke = _strokes.last;
    if (currentStroke.isNotEmpty) {
      final previousPoint = currentStroke.last;
      final minimumDistance = _isStylusKind(event.kind)
          ? _stylusMinimumDistance
          : _touchMinimumDistance;
      if ((previousPoint - point).distance < minimumDistance) {
        return;
      }
    }

    _appendPointToStroke(currentStroke, point);
    _notifyStrokePaint();
    _refreshUiIfNeeded(
      hadSignature: hadSignature,
      stylusWasActive: stylusWasActive,
    );
  }

  void _endStroke(PointerEvent event) {
    if (_activePointer != event.pointer) return;

    final stylusWasActive = _stylusSessionActive;
    _activePointer = null;
    _activePointerKind = null;

    if (stylusWasActive != _stylusSessionActive) {
      setState(() {});
    }
  }

  bool _supportsSignatureInput(ui.PointerDeviceKind kind) {
    return kind == ui.PointerDeviceKind.touch ||
        kind == ui.PointerDeviceKind.mouse ||
        kind == ui.PointerDeviceKind.stylus ||
        kind == ui.PointerDeviceKind.invertedStylus;
  }

  bool _allowsInputKind(ui.PointerDeviceKind kind) {
    if (_stylusSessionActive && kind == ui.PointerDeviceKind.touch) {
      return false;
    }
    return true;
  }

  bool _isStylusKind(ui.PointerDeviceKind? kind) {
    return kind == ui.PointerDeviceKind.stylus ||
        kind == ui.PointerDeviceKind.invertedStylus;
  }

  Offset? _localPointFor(Offset globalPosition) {
    final renderObject =
        _signatureKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderObject == null || !renderObject.hasSize) {
      return null;
    }

    final local = renderObject.globalToLocal(globalPosition);
    final size = renderObject.size;
    if (local.dx < 0 ||
        local.dy < 0 ||
        local.dx > size.width ||
        local.dy > size.height) {
      return null;
    }
    return local;
  }

  void _appendPointToStroke(List<Offset> stroke, Offset point) {
    stroke.add(point);
    _strokePointCount += 1;
    _extendSignatureBounds(point);
  }

  void _extendSignatureBounds(Offset point) {
    final currentBounds = _strokeExtents;
    if (currentBounds == null) {
      _strokeExtents = Rect.fromLTWH(point.dx, point.dy, 0, 0);
      return;
    }

    _strokeExtents = Rect.fromLTRB(
      math.min(currentBounds.left, point.dx),
      math.min(currentBounds.top, point.dy),
      math.max(currentBounds.right, point.dx),
      math.max(currentBounds.bottom, point.dy),
    );
  }

  void _notifyStrokePaint() {
    _strokeRevision.value = _strokeRevision.value + 1;
  }

  void _refreshUiIfNeeded({
    required bool hadSignature,
    required bool stylusWasActive,
  }) {
    if (hadSignature != _hasSignature ||
        stylusWasActive != _stylusSessionActive) {
      setState(() {});
    }
  }

  Future<void> _clearSignature() async {
    if (_strokes.isEmpty) return;

    setState(() {
      _strokes.clear();
      _strokePointCount = 0;
      _strokeExtents = null;
      _activePointer = null;
      _activePointerKind = null;
    });
    _notifyStrokePaint();
  }

  Future<void> _saveSignature() async {
    if (_exporting) return;
    if (!_hasSignature) {
      showAppFeedbackBanner(
        context,
        'Firma dentro del recuadro con el dedo o con un lapiz optico.',
        tone: AppFeedbackTone.error,
      );
      return;
    }

    if (_signatureKey.currentContext?.findRenderObject() == null) {
      showAppFeedbackBanner(
        context,
        'No pudimos preparar la firma. Intenta nuevamente.',
        tone: AppFeedbackTone.error,
      );
      return;
    }

    setState(() {
      _exporting = true;
    });

    try {
      final bytes = await _exportSignatureBytes();
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        showAppFeedbackBanner(
          context,
          'No pudimos guardar la firma. Intenta otra vez.',
          tone: AppFeedbackTone.error,
        );
        return;
      }

      Navigator.of(context).pop(bytes);
    } catch (_) {
      if (!mounted) return;
      showAppFeedbackBanner(
        context,
        'No pudimos exportar la firma. Intenta nuevamente.',
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
        });
      }
    }
  }

  Future<Uint8List?> _exportSignatureBytes() async {
    final bounds = _signatureBounds();
    if (bounds == null) {
      return null;
    }

    const padding = 18.0;
    const minWidth = 220.0;
    const minHeight = 96.0;
    const scale = 3.0;
    final canvasWidth = math.max(minWidth, bounds.width + (padding * 2));
    final canvasHeight = math.max(minHeight, bounds.height + (padding * 2));
    final translateX = ((canvasWidth - bounds.width) / 2) - bounds.left;
    final translateY = ((canvasHeight - bounds.height) / 2) - bounds.top;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.scale(scale, scale);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, canvasWidth, canvasHeight),
      Paint()..color = Colors.white,
    );
    canvas.translate(translateX, translateY);
    paintSignatureStrokes(canvas, _strokes);

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (canvasWidth * scale).round(),
      (canvasHeight * scale).round(),
    );

    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
    } finally {
      image.dispose();
      picture.dispose();
    }
  }

  Rect? _signatureBounds() {
    final bounds = _strokeExtents;
    if (bounds == null) {
      return null;
    }

    const strokePadding = 8.0;
    return Rect.fromLTRB(
      bounds.left - strokePadding,
      bounds.top - strokePadding,
      bounds.right + strokePadding,
      bounds.bottom + strokePadding,
    );
  }

  @override
  void dispose() {
    _strokeRevision.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: 'Firma de entrega',
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: RepaintBoundary(
                key: _signatureKey,
                child: Listener(
                  onPointerDown: _startStroke,
                  onPointerMove: _appendStroke,
                  onPointerUp: _endStroke,
                  onPointerCancel: _endStroke,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: AppTheme.blue, width: 1.5),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x140F1E3D),
                          blurRadius: 24,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: CustomPaint(
                      foregroundPainter: _SignaturePainter(
                        strokes: _strokes,
                        repaint: _strokeRevision,
                      ),
                      child: Stack(
                        children: [
                          if (!_hasSignature)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 24),
                                child: Text(
                                  'Firma aqui',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Color(0x806274A3),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 22,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _stylusSessionActive
                  ? 'Lapiz detectado: priorizamos el trazo del lapiz para evitar toques accidentales.'
                  : (_hasSignature
                        ? 'Firma lista para guardar'
                        : 'Traza una firma continua para registrar la entrega'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.blueMid,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 12),
            AppActionTray(
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _exporting ? null : _clearSignature,
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('Limpiar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _exporting ? null : _saveSignature,
                      icon: _exporting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(
                        _exporting ? 'Guardando...' : 'Guardar firma',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter({required this.strokes, required Listenable repaint})
    : super(repaint: repaint);

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    paintSignatureStrokes(canvas, strokes);
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) {
    return false;
  }
}

void paintSignatureStrokes(Canvas canvas, List<List<Offset>> strokes) {
  final paint = Paint()
    ..color = AppTheme.blueDark
    ..strokeWidth = 2.8
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  for (final stroke in strokes) {
    if (stroke.isEmpty) {
      continue;
    }
    if (stroke.length == 1) {
      canvas.drawCircle(stroke.first, 1.6, paint..style = PaintingStyle.fill);
      paint.style = PaintingStyle.stroke;
      continue;
    }

    final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
    if (stroke.length == 2) {
      path.lineTo(stroke.last.dx, stroke.last.dy);
      canvas.drawPath(path, paint);
      continue;
    }

    for (var index = 1; index < stroke.length - 1; index += 1) {
      final point = stroke[index];
      final nextPoint = stroke[index + 1];
      final midPoint = Offset(
        (point.dx + nextPoint.dx) / 2,
        (point.dy + nextPoint.dy) / 2,
      );
      path.quadraticBezierTo(point.dx, point.dy, midPoint.dx, midPoint.dy);
    }

    final lastPoint = stroke.last;
    path.lineTo(lastPoint.dx, lastPoint.dy);
    canvas.drawPath(path, paint);
  }
}
