import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/utilidades/package_code_classifier.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/dominio/modelos/scanned_ficha_data.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/dominio/repositorios/scanner_repository.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/utilidades/ocr_parser.dart';

enum PackageLookupRecognitionMode { barcode, ocr }

class _FrameInputBytes {
  const _FrameInputBytes({
    required this.bytes,
    required this.format,
    required this.bytesPerRow,
    required this.size,
  });

  final Uint8List bytes;
  final InputImageFormat format;
  final int bytesPerRow;
  final Size size;
}

class _CroppedBytes {
  const _CroppedBytes({
    required this.bytes,
    required this.width,
    required this.height,
    required this.bytesPerRow,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final int bytesPerRow;
}

class _IntCropRect {
  const _IntCropRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final int left;
  final int top;
  final int width;
  final int height;
}

class ScannerController extends ChangeNotifier {
  ScannerController({
    required this.scanRepository,
    this.scanAreaWidthFactor = 0.94,
    this.scanAreaHeightFactor = 0.36,
    this.cameraResolutionPreset = ResolutionPreset.veryHigh,
    this.barcodeFormats = const <BarcodeFormat>[BarcodeFormat.all],
  });

  final ScanRepository scanRepository;
  final double scanAreaWidthFactor;
  final double scanAreaHeightFactor;
  final ResolutionPreset cameraResolutionPreset;
  final List<BarcodeFormat> barcodeFormats;
  TextRecognizer? _textRecognizer;
  BarcodeScanner? _barcodeScanner;
  final ValueNotifier<int> _cameraTick = ValueNotifier<int>(0);
  final ValueNotifier<int> _scanTick = ValueNotifier<int>(0);

  CameraController? _cameraController;
  Future<void>? _cameraInitFuture;
  int _cameraSessionVersion = 0;
  bool _initializingCamera = false;
  bool _isProcessing = false;
  bool _torchEnabled = false;
  bool _cameraPermissionDenied = false;
  bool _autoLookupActive = false;
  bool _processingAutoLookupFrame = false;
  bool _forceNextAutoLookupFrame = false;
  bool _disposed = false;
  String _barcodeResult = 'Sin detectar';
  String _ocrResult = 'Sin detectar';
  String _status = 'Activa la cámara para empezar.';
  ScannedFichaData? _lastData;
  CameraDescription? _activeCamera;
  ValueChanged<String>? _autoLookupDetected;
  bool Function(String code)? _autoLookupCanDetect;
  PackageLookupRecognitionMode _autoLookupRecognitionMode =
      PackageLookupRecognitionMode.barcode;
  DateTime? _lastAutoLookupFrameAt;
  String? _lastAutoLookupCandidate;
  int _lastAutoLookupCandidateHits = 0;
  int _lastAutoLookupCandidateMisses = 0;
  double? _scanViewportAspectRatio;

  static const Duration _autoLookupFrameInterval = Duration(milliseconds: 120);
  static const int _autoLookupBarcodeStableHits = 1;
  static const int _autoLookupOcrStableHits = 2;
  static const Map<DeviceOrientation, int> _deviceOrientations =
      <DeviceOrientation, int>{
        DeviceOrientation.portraitUp: 0,
        DeviceOrientation.landscapeLeft: 90,
        DeviceOrientation.portraitDown: 180,
        DeviceOrientation.landscapeRight: 270,
      };

  CameraController? get cameraController => _cameraController;
  ValueListenable<int> get cameraListenable => _cameraTick;
  ValueListenable<int> get scanListenable => _scanTick;
  bool get initializingCamera => _initializingCamera;
  bool get isProcessing => _isProcessing;
  bool get torchEnabled => _torchEnabled;
  bool get cameraPermissionDenied => _cameraPermissionDenied;
  String get barcodeResult => _barcodeResult;
  String get ocrResult => _ocrResult;
  String get status => _status;
  ScannedFichaData? get lastData => _lastData;
  bool get hasDetectedContent =>
      _barcodeResult != 'Sin detectar' || _ocrResult != 'Sin detectar';
  bool get cameraReady =>
      _cameraController != null && _cameraController!.value.isInitialized;

  void updateScanViewportSize(Size size) {
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0 ||
        size.height <= 0) {
      return;
    }
    _scanViewportAspectRatio = size.width / size.height;
  }

  void _notifyCameraUi() {
    if (_disposed) return;
    _cameraTick.value = _cameraTick.value + 1;
    notifyListeners();
  }

  void _notifyScanUi() {
    if (_disposed) return;
    _scanTick.value = _scanTick.value + 1;
    notifyListeners();
  }

  void prepareCamera() {
    if (cameraReady || _cameraInitFuture != null) return;
    unawaited(initCamera());
  }

  Future<void> initCamera() async {
    if (_disposed) return;
    if (cameraReady) return;
    if (_cameraInitFuture != null) {
      await _cameraInitFuture;
      return;
    }

    _initializingCamera = true;
    _notifyCameraUi();
    _cameraInitFuture = _doInitCamera(_cameraSessionVersion);
    try {
      await _cameraInitFuture;
    } finally {
      _cameraInitFuture = null;
      _initializingCamera = false;
      _notifyCameraUi();
    }
  }

  Future<void> _doInitCamera(int sessionVersion) async {
    try {
      _cameraPermissionDenied = false;
      final cameras = await availableCameras();
      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        backCamera,
        cameraResolutionPreset,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.nv21,
      );

      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (_disposed || sessionVersion != _cameraSessionVersion) {
        await controller.dispose();
        return;
      }
      _torchEnabled = false;
      _activeCamera = backCamera;
      _cameraController = controller;
      _notifyCameraUi();
      unawaited(_configureCameraControls(controller));
    } on CameraException catch (error) {
      final lowerCode = error.code.toLowerCase();
      final denied = lowerCode.contains('cameraaccessdenied');
      _cameraPermissionDenied = denied;
      _status = denied
          ? 'Necesitamos permiso para usar la cámara. Actívalo en ajustes.'
          : 'No pudimos abrir la cámara. Intenta nuevamente.';
      _notifyScanUi();
    } catch (_) {
      _cameraPermissionDenied = false;
      _status = 'No pudimos abrir la cámara. Intenta nuevamente.';
      _notifyScanUi();
    }
  }

  Future<void> _configureCameraControls(CameraController controller) async {
    if (_disposed || _cameraController != controller) return;
    try {
      await controller.setFlashMode(FlashMode.off);
    } catch (_) {}
    try {
      await controller.setFocusMode(FocusMode.auto);
    } catch (_) {
      // Continue even if the device does not expose focus controls.
    }
    try {
      await controller.setExposureMode(ExposureMode.auto);
    } catch (_) {}
    try {
      await controller.setFocusPoint(const Offset(0.5, 0.5));
    } catch (_) {}
    try {
      await controller.setExposurePoint(const Offset(0.5, 0.5));
    } catch (_) {}
  }

  Future<void> scanFicha() async {
    if (_isProcessing) return;
    if (!cameraReady) {
      await initCamera();
    }
    if (!cameraReady) return;
    final controller = _cameraController!;

    _isProcessing = true;
    _status = 'Estamos leyendo la imagen...';
    _notifyScanUi();

    try {
      final photo = await controller.takePicture();
      await _scanFromImagePath(
        photo.path,
        useRoiFiltering: true,
        deleteImageOnFinish: true,
      );
    } catch (_) {
      _status = 'No pudimos leer la imagen. Intenta nuevamente.';
    } finally {
      _isProcessing = false;
      _notifyScanUi();
    }
  }

  Future<void> toggleTorch() async {
    if (!cameraReady) {
      await initCamera();
    }
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    final nextMode = _torchEnabled ? FlashMode.off : FlashMode.torch;
    try {
      await controller.setFlashMode(nextMode);
      _torchEnabled = nextMode == FlashMode.torch;
      _notifyCameraUi();
    } catch (_) {
      _status = 'No pudimos cambiar la linterna.';
      _notifyScanUi();
    }
  }

  Future<void> startPackageLookupAutoScan({
    required ValueChanged<String> onCodeDetected,
    bool Function(String code)? canDetectCode,
    PackageLookupRecognitionMode recognitionMode =
        PackageLookupRecognitionMode.barcode,
  }) async {
    if (_disposed) return;
    _autoLookupDetected = onCodeDetected;
    _autoLookupCanDetect = canDetectCode;
    _autoLookupRecognitionMode = recognitionMode;
    if (!cameraReady) {
      await initCamera();
    }
    if (_disposed) return;
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    if (_autoLookupActive || controller.value.isStreamingImages) return;

    _autoLookupActive = true;
    _forceNextAutoLookupFrame = true;
    _lastAutoLookupCandidate = null;
    _lastAutoLookupCandidateHits = 0;
    _lastAutoLookupCandidateMisses = 0;
    _lastAutoLookupFrameAt = null;
    _status = recognitionMode == PackageLookupRecognitionMode.barcode
        ? 'Enfoca el código de barras dentro del marco.'
        : 'Enfoca el código impreso dentro del marco.';
    _notifyScanUi();

    try {
      await controller.startImageStream(_processPackageLookupFrame);
    } catch (_) {
      _autoLookupActive = false;
      _status =
          'No pudimos activar la lectura automatica. Toma una foto para intentar.';
      _notifyScanUi();
    }
  }

  Future<void> stopPackageLookupAutoScan() async {
    _autoLookupActive = false;
    _forceNextAutoLookupFrame = false;
    _lastAutoLookupCandidate = null;
    _lastAutoLookupCandidateHits = 0;
    _lastAutoLookupCandidateMisses = 0;
    _lastAutoLookupFrameAt = null;
    _autoLookupCanDetect = null;

    final controller = _cameraController;
    if (controller == null ||
        !controller.value.isInitialized ||
        !controller.value.isStreamingImages) {
      return;
    }

    try {
      await controller.stopImageStream();
    } catch (_) {
      // The camera may already be stopping or disposed.
    }
  }

  void clearScanOutput({
    String statusMessage = 'Activa la cámara para empezar.',
  }) {
    _barcodeResult = 'Sin detectar';
    _ocrResult = 'Sin detectar';
    _lastData = null;
    _status = statusMessage;
    _notifyScanUi();
  }

  Future<void> _processPackageLookupFrame(CameraImage image) async {
    if (_disposed ||
        !_autoLookupActive ||
        _processingAutoLookupFrame ||
        _isProcessing) {
      return;
    }

    final forcedFrame = _forceNextAutoLookupFrame;
    _forceNextAutoLookupFrame = false;

    final now = DateTime.now();
    final lastFrameAt = _lastAutoLookupFrameAt;
    if (!forcedFrame &&
        lastFrameAt != null &&
        now.difference(lastFrameAt) < _autoLookupFrameInterval) {
      return;
    }
    _lastAutoLookupFrameAt = now;
    _processingAutoLookupFrame = true;

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) return;

      final isBarcodeMode =
          _autoLookupRecognitionMode == PackageLookupRecognitionMode.barcode;
      String? code;
      var hadDetectedContent = false;
      if (isBarcodeMode) {
        final barcodeScanner = _barcodeScanner ??= BarcodeScanner(
          formats: barcodeFormats,
        );
        final detectedBarcodes = await barcodeScanner.processImage(inputImage);
        hadDetectedContent = detectedBarcodes.isNotEmpty;
        code = _extractPackageLookupCodeFromLiveBarcodes(detectedBarcodes);
      } else {
        final textRecognizer = _textRecognizer ??= TextRecognizer();
        final recognizedText = await textRecognizer.processImage(inputImage);
        hadDetectedContent = recognizedText.text.trim().isNotEmpty;
        code = _extractOcrLookupCandidate(recognizedText.text);
      }
      if (!_autoLookupActive) return;

      final requiredHits = isBarcodeMode
          ? _autoLookupBarcodeStableHits
          : _autoLookupOcrStableHits;

      if (code == null) {
        if (hadDetectedContent) {
          _lastAutoLookupCandidateMisses += 1;
          if (_lastAutoLookupCandidateMisses > 2) {
            _lastAutoLookupCandidate = null;
            _lastAutoLookupCandidateHits = 0;
            _lastAutoLookupCandidateMisses = 0;
          }
        }
        return;
      }

      if (_lastAutoLookupCandidate == code) {
        _lastAutoLookupCandidateHits += 1;
      } else {
        _lastAutoLookupCandidate = code;
        _lastAutoLookupCandidateHits = 1;
      }
      _lastAutoLookupCandidateMisses = 0;

      if (_lastAutoLookupCandidateHits >= requiredHits) {
        final canDetectCode = _autoLookupCanDetect;
        if (canDetectCode != null && !canDetectCode(code)) {
          return;
        }
        unawaited(_completePackageLookupAutoScan(code));
      }
    } catch (_) {
      // Live frames are best-effort; the manual capture remains available.
    } finally {
      _processingAutoLookupFrame = false;
    }
  }

  InputImage? _inputImageFromCameraImage(
    CameraImage image, {
    bool cropToScanArea = true,
  }) {
    final camera = _activeCamera;
    final controller = _cameraController;
    if (camera == null || controller == null) return null;

    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      final orientation =
          _deviceOrientations[controller.value.lockedCaptureOrientation ??
              controller.value.deviceOrientation];
      if (orientation == null) return null;
      final rotationCompensation =
          camera.lensDirection == CameraLensDirection.front
          ? (sensorOrientation + orientation) % 360
          : (sensorOrientation - orientation + 360) % 360;
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) return null;

    final format = _resolveInputImageFormat(image);
    if (format == null) return null;

    final frameBytes = _frameBytesForInputImage(
      image,
      format,
      rotation,
      cropToScanArea: cropToScanArea,
    );
    if (frameBytes == null) {
      return null;
    }

    return InputImage.fromBytes(
      bytes: frameBytes.bytes,
      metadata: InputImageMetadata(
        size: frameBytes.size,
        rotation: rotation,
        format: frameBytes.format,
        bytesPerRow: frameBytes.bytesPerRow,
      ),
    );
  }

  InputImageFormat? _resolveInputImageFormat(CameraImage image) {
    final rawFormat = InputImageFormatValue.fromRawValue(image.format.raw);
    if (rawFormat != null) return rawFormat;

    switch (image.format.group) {
      case ImageFormatGroup.nv21:
        return InputImageFormat.nv21;
      case ImageFormatGroup.yuv420:
        return Platform.isAndroid
            ? InputImageFormat.yuv_420_888
            : InputImageFormat.yuv420;
      case ImageFormatGroup.bgra8888:
        return InputImageFormat.bgra8888;
      case ImageFormatGroup.jpeg:
      case ImageFormatGroup.unknown:
        return null;
    }
  }

  _FrameInputBytes? _frameBytesForInputImage(
    CameraImage image,
    InputImageFormat format,
    InputImageRotation rotation, {
    bool cropToScanArea = true,
  }) {
    final rawRoi = cropToScanArea
        ? _scanRoiInCameraCoordinates(image, rotation)
        : Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    if (Platform.isAndroid) {
      if (format == InputImageFormat.nv21 && image.planes.length == 1) {
        final plane = image.planes.first;
        final cropped = _cropNv21(
          plane.bytes,
          width: image.width,
          height: image.height,
          cropRect: rawRoi,
        );
        if (cropped == null) return null;
        return _FrameInputBytes(
          bytes: cropped.bytes,
          format: InputImageFormat.nv21,
          bytesPerRow: cropped.bytesPerRow,
          size: Size(cropped.width.toDouble(), cropped.height.toDouble()),
        );
      }

      if (format == InputImageFormat.yuv_420_888 && image.planes.length >= 3) {
        final cropped = _cropNv21(
          _convertYuv420ToNv21(image),
          width: image.width,
          height: image.height,
          cropRect: rawRoi,
        );
        if (cropped == null) return null;
        return _FrameInputBytes(
          bytes: cropped.bytes,
          format: InputImageFormat.nv21,
          bytesPerRow: cropped.bytesPerRow,
          size: Size(cropped.width.toDouble(), cropped.height.toDouble()),
        );
      }
      return null;
    }

    if (Platform.isIOS &&
        format == InputImageFormat.bgra8888 &&
        image.planes.length == 1) {
      final plane = image.planes.first;
      final cropped = _cropBgra8888(
        plane.bytes,
        width: image.width,
        height: image.height,
        bytesPerRow: plane.bytesPerRow,
        cropRect: rawRoi,
      );
      if (cropped == null) return null;
      return _FrameInputBytes(
        bytes: cropped.bytes,
        format: InputImageFormat.bgra8888,
        bytesPerRow: cropped.bytesPerRow,
        size: Size(cropped.width.toDouble(), cropped.height.toDouble()),
      );
    }

    return null;
  }

  Rect _scanRoiInCameraCoordinates(
    CameraImage image,
    InputImageRotation rotation,
  ) {
    final rawSize = Size(image.width.toDouble(), image.height.toDouble());
    final uprightSize = _isQuarterTurn(rotation)
        ? Size(rawSize.height, rawSize.width)
        : rawSize;
    final uprightRoi = _buildScanRoi(uprightSize);

    switch (rotation) {
      case InputImageRotation.rotation0deg:
        return uprightRoi;
      case InputImageRotation.rotation90deg:
        return Rect.fromLTRB(
          uprightRoi.top,
          rawSize.height - uprightRoi.right,
          uprightRoi.bottom,
          rawSize.height - uprightRoi.left,
        );
      case InputImageRotation.rotation180deg:
        return Rect.fromLTRB(
          rawSize.width - uprightRoi.right,
          rawSize.height - uprightRoi.bottom,
          rawSize.width - uprightRoi.left,
          rawSize.height - uprightRoi.top,
        );
      case InputImageRotation.rotation270deg:
        return Rect.fromLTRB(
          rawSize.width - uprightRoi.bottom,
          uprightRoi.left,
          rawSize.width - uprightRoi.top,
          uprightRoi.right,
        );
    }
  }

  bool _isQuarterTurn(InputImageRotation rotation) {
    return rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
  }

  _CroppedBytes? _cropNv21(
    Uint8List bytes, {
    required int width,
    required int height,
    required Rect cropRect,
  }) {
    final crop = _alignCropRect(cropRect, width, height, requireEven: true);
    if (crop == null) return null;

    final output = Uint8List(
      (crop.width * crop.height) + ((crop.width * crop.height) ~/ 2),
    );

    var outputOffset = 0;
    for (var row = 0; row < crop.height; row++) {
      final inputOffset = ((crop.top + row) * width) + crop.left;
      output.setRange(
        outputOffset,
        outputOffset + crop.width,
        bytes,
        inputOffset,
      );
      outputOffset += crop.width;
    }

    final inputUvOffset = width * height;
    final outputUvOffset = crop.width * crop.height;
    for (var row = 0; row < crop.height ~/ 2; row++) {
      final inputOffset =
          inputUvOffset + (((crop.top ~/ 2) + row) * width) + crop.left;
      final outputOffset = outputUvOffset + (row * crop.width);
      output.setRange(
        outputOffset,
        outputOffset + crop.width,
        bytes,
        inputOffset,
      );
    }

    return _CroppedBytes(
      bytes: output,
      width: crop.width,
      height: crop.height,
      bytesPerRow: crop.width,
    );
  }

  _CroppedBytes? _cropBgra8888(
    Uint8List bytes, {
    required int width,
    required int height,
    required int bytesPerRow,
    required Rect cropRect,
  }) {
    final crop = _alignCropRect(cropRect, width, height);
    if (crop == null) return null;

    const bytesPerPixel = 4;
    final outputBytesPerRow = crop.width * bytesPerPixel;
    final output = Uint8List(outputBytesPerRow * crop.height);

    for (var row = 0; row < crop.height; row++) {
      final inputOffset =
          ((crop.top + row) * bytesPerRow) + (crop.left * bytesPerPixel);
      final outputOffset = row * outputBytesPerRow;
      output.setRange(
        outputOffset,
        outputOffset + outputBytesPerRow,
        bytes,
        inputOffset,
      );
    }

    return _CroppedBytes(
      bytes: output,
      width: crop.width,
      height: crop.height,
      bytesPerRow: outputBytesPerRow,
    );
  }

  _IntCropRect? _alignCropRect(
    Rect rect,
    int imageWidth,
    int imageHeight, {
    bool requireEven = false,
  }) {
    var left = rect.left.floor().clamp(0, imageWidth - 1);
    var top = rect.top.floor().clamp(0, imageHeight - 1);
    var right = rect.right.ceil().clamp(left + 1, imageWidth);
    var bottom = rect.bottom.ceil().clamp(top + 1, imageHeight);

    if (requireEven) {
      left = left.isEven ? left : left - 1;
      top = top.isEven ? top : top - 1;
      right = right.isEven ? right : right - 1;
      bottom = bottom.isEven ? bottom : bottom - 1;
      if (right <= left) right = (left + 2).clamp(0, imageWidth);
      if (bottom <= top) bottom = (top + 2).clamp(0, imageHeight);
    }

    final cropWidth = right - left;
    final cropHeight = bottom - top;
    if (cropWidth <= 0 || cropHeight <= 0) return null;

    return _IntCropRect(
      left: left,
      top: top,
      width: cropWidth,
      height: cropHeight,
    );
  }

  Uint8List _convertYuv420ToNv21(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final uvWidth = width ~/ 2;
    final uvHeight = height ~/ 2;
    final output = Uint8List((width * height) + (uvWidth * uvHeight * 2));

    var outputOffset = 0;
    final yPixelStride = yPlane.bytesPerPixel ?? 1;
    for (var row = 0; row < height; row++) {
      var inputOffset = row * yPlane.bytesPerRow;
      for (var col = 0; col < width; col++) {
        output[outputOffset++] = yPlane.bytes[inputOffset];
        inputOffset += yPixelStride;
      }
    }

    final uPixelStride = uPlane.bytesPerPixel ?? 1;
    final vPixelStride = vPlane.bytesPerPixel ?? 1;
    for (var row = 0; row < uvHeight; row++) {
      var uOffset = row * uPlane.bytesPerRow;
      var vOffset = row * vPlane.bytesPerRow;
      for (var col = 0; col < uvWidth; col++) {
        output[outputOffset++] = vPlane.bytes[vOffset];
        output[outputOffset++] = uPlane.bytes[uOffset];
        uOffset += uPixelStride;
        vOffset += vPixelStride;
      }
    }

    return output;
  }

  String? _extractPackageLookupCodeFromLiveBarcodes(List<Barcode> barcodes) {
    if (barcodes.isEmpty) return null;

    return _extractPackageLookupCode(_collectBarcodes(barcodes));
  }

  Future<void> _completePackageLookupAutoScan(String code) async {
    if (!_autoLookupActive) return;
    final callback = _autoLookupDetected;
    _autoLookupActive = false;
    await stopPackageLookupAutoScan();
    if (callback == null) return;

    final isBarcodeMode =
        _autoLookupRecognitionMode == PackageLookupRecognitionMode.barcode;
    await _applyScanOutput(
      barcodeText: isBarcodeMode ? code : '',
      ocrText: isBarcodeMode ? '' : code,
      statusMessage: isBarcodeMode
          ? 'Codigo de barras detectado.'
          : 'Texto del código detectado.',
    );
    callback(code);
  }

  Future<void> scanFichaFromImagePath(
    String imagePath, {
    Rect? normalizedBarcodeRoi,
    Rect? normalizedOcrRoi,
    Size? imageSize,
    bool useRoiFiltering = true,
    bool packageLookupMode = false,
    PackageLookupRecognitionMode packageLookupRecognitionMode =
        PackageLookupRecognitionMode.barcode,
    bool deleteImageOnFinish = false,
  }) async {
    if (_isProcessing) return;

    _isProcessing = true;
    _status = 'Estamos leyendo la imagen de la galería...';
    _notifyScanUi();

    try {
      await _scanFromImagePath(
        imagePath,
        normalizedBarcodeRoi: normalizedBarcodeRoi,
        normalizedOcrRoi: normalizedOcrRoi,
        imageSize: imageSize,
        useRoiFiltering: useRoiFiltering,
        packageLookupMode: packageLookupMode,
        packageLookupRecognitionMode: packageLookupRecognitionMode,
        deleteImageOnFinish: deleteImageOnFinish,
      );
    } catch (_) {
      _status = 'No pudimos leer la imagen. Intenta nuevamente.';
    } finally {
      _isProcessing = false;
      _notifyScanUi();
    }
  }

  Future<void> _scanFromImagePath(
    String imagePath, {
    Rect? normalizedBarcodeRoi,
    Rect? normalizedOcrRoi,
    Size? imageSize,
    bool useRoiFiltering = true,
    bool packageLookupMode = false,
    PackageLookupRecognitionMode packageLookupRecognitionMode =
        PackageLookupRecognitionMode.barcode,
    bool deleteImageOnFinish = false,
  }) async {
    try {
      if (packageLookupMode &&
          packageLookupRecognitionMode == PackageLookupRecognitionMode.ocr) {
        final ocrText = await _recognizeTextFromImageRoi(
          imagePath,
          normalizedRoi: normalizedOcrRoi,
          useScanArea: useRoiFiltering,
        );
        final packageLookupCode = _extractOcrLookupCandidate(ocrText) ?? '';

        await _applyScanOutput(
          barcodeText: '',
          ocrText: packageLookupCode,
          statusMessage: packageLookupCode.isEmpty
              ? 'No se pudo reconocer el código impreso.'
              : 'Texto del código detectado.',
        );
        return;
      }

      final barcodeScanner = _barcodeScanner ??= BarcodeScanner(
        formats: barcodeFormats,
      );
      final inputImage = InputImage.fromFilePath(imagePath);
      final resolvedSize = imageSize ?? await _readImageSize(imagePath);
      final fullRoi = Rect.fromLTWH(
        0,
        0,
        resolvedSize.width,
        resolvedSize.height,
      );
      final defaultBarcodeRoi = useRoiFiltering
          ? _buildScanRoi(resolvedSize)
          : fullRoi;

      final barcodeRoi = normalizedBarcodeRoi == null
          ? defaultBarcodeRoi
          : _buildRoiFromNormalizedRect(
              size: resolvedSize,
              normalizedRoi: normalizedBarcodeRoi,
            );
      final allBarcodes = await barcodeScanner.processImage(inputImage);
      final barcodes = allBarcodes
          .where((barcode) => _rectCenterInRoi(barcode.boundingBox, barcodeRoi))
          .toList();
      final barcodeText = _collectBarcodes(barcodes);

      if (packageLookupMode) {
        final packageLookupCode =
            _extractPackageLookupCode(barcodeText.trim()) ?? '';
        final nothingDetected = packageLookupCode.isEmpty;

        await _applyScanOutput(
          barcodeText: packageLookupCode,
          ocrText: '',
          statusMessage: nothingDetected
              ? 'No se pudo reconocer un código de barras válido.'
              : 'Codigo de barras detectado.',
        );
        return;
      }

      final textRecognizer = _textRecognizer ??= TextRecognizer();
      final ocrRoi = normalizedOcrRoi == null
          ? defaultBarcodeRoi
          : _buildRoiFromNormalizedRect(
              size: resolvedSize,
              normalizedRoi: normalizedOcrRoi,
            );
      final recognizedText = await textRecognizer.processImage(inputImage);
      final ocrRoiBarcodes = allBarcodes
          .where((barcode) => _rectCenterInRoi(barcode.boundingBox, ocrRoi))
          .toList();
      final ocrText = _extractTextFromRoiWithoutBarcodes(
        recognizedText,
        ocrRoiBarcodes,
        ocrRoi,
      );

      final normalizedOcrText = ocrText.trim();
      final normalizedBarcodeText = barcodeText.trim();
      final nothingDetected =
          normalizedBarcodeText.isEmpty && normalizedOcrText.isEmpty;

      await _applyScanOutput(
        barcodeText: normalizedBarcodeText,
        ocrText: normalizedOcrText,
        statusMessage: nothingDetected
            ? 'No se detectó información. Ajusta distancia, luz y encuadre.'
            : 'Resultados detectados.',
      );
    } finally {
      if (deleteImageOnFinish) {
        await _cleanupScanImage(imagePath);
      }
    }
  }

  Future<void> _applyScanOutput({
    required String barcodeText,
    required String ocrText,
    required String statusMessage,
  }) async {
    _barcodeResult = barcodeText.isEmpty ? 'Sin detectar' : barcodeText;
    _ocrResult = ocrText.isEmpty ? 'Sin detectar' : ocrText;
    _status = statusMessage;
    try {
      _lastData = await compute(parseScannedFichaData, {
        'barcodeText': barcodeText,
        'ocrText': ocrText,
      });
    } catch (e) {
      try {
        _lastData = parseScannedFichaData({
          'barcodeText': barcodeText,
          'ocrText': ocrText,
        });
      } catch (e) {
        _lastData = ScannedFichaData(
          barcode: barcodeText.trim(),
          nombre: '',
          direccion: '',
          telefono: '',
          ocrRaw: ocrText,
          ocrTokens: const [],
        );
      }
    }
    _notifyScanUi();
  }

  String _collectBarcodes(List<Barcode> barcodes) {
    if (barcodes.isEmpty) return '';

    final sorted = [...barcodes]
      ..sort((a, b) => _barcodeArea(b).compareTo(_barcodeArea(a)));

    final values = <String>{};
    for (final barcode in sorted) {
      final value = (barcode.displayValue ?? barcode.rawValue ?? '').trim();
      if (value.isNotEmpty) values.add(value);
    }
    return values.join('\n');
  }

  double _barcodeArea(Barcode barcode) {
    final rect = barcode.boundingBox;
    return rect.width * rect.height;
  }

  String? _extractPackageLookupCode(String rawValue) {
    if (rawValue.trim().isEmpty) return null;

    final segments = rawValue
        .split(RegExp(r'[\r\n]+'))
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty);

    for (final segment in segments) {
      for (final candidate in PackageCodeClassifier.extractSearchCandidates(
        segment,
      )) {
        return candidate;
      }
    }

    for (final candidate in PackageCodeClassifier.extractSearchCandidates(
      rawValue,
    )) {
      return candidate;
    }
    return null;
  }

  String? _extractOcrLookupCandidate(String rawValue) {
    final validCode = _extractPackageLookupCode(rawValue);
    if (validCode != null) return validCode;

    for (final candidate
        in PackageCodeClassifier.extractSearchCandidatesFromOcr(rawValue)) {
      return candidate;
    }

    final candidates =
        rawValue
            .split(RegExp(r'[\r\n]+'))
            .map(
              (line) => line.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), ''),
            )
            .where(
              (candidate) =>
                  candidate.length >= 6 &&
                  RegExp(r'[A-Z]').hasMatch(candidate) &&
                  RegExp(r'\d').allMatches(candidate).length >= 4,
            )
            .toList(growable: false)
          ..sort((first, second) => second.length.compareTo(first.length));
    return candidates.isEmpty ? null : candidates.first;
  }

  String _extractTextFromRoiWithoutBarcodes(
    RecognizedText recognizedText,
    List<Barcode> barcodes,
    Rect roi,
  ) {
    final lines = recognizedText.blocks.expand((block) => block.lines).toList();
    if (lines.isEmpty) return recognizedText.text.trim();

    final filteredLines = lines
        .where(
          (line) =>
              line.text.trim().isNotEmpty &&
              _rectCenterInRoi(line.boundingBox, roi) &&
              !_isOverBarcode(line.boundingBox, barcodes),
        )
        .map((line) => line.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();

    if (filteredLines.isNotEmpty) return filteredLines.join('\n');

    final nonBarcodeLines = lines
        .where(
          (line) =>
              line.text.trim().isNotEmpty &&
              !_isOverBarcode(line.boundingBox, barcodes),
        )
        .map((line) => line.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();

    if (nonBarcodeLines.isNotEmpty) return nonBarcodeLines.join('\n');
    return recognizedText.text.trim();
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

  Future<String> _recognizeTextFromImageRoi(
    String imagePath, {
    required Rect? normalizedRoi,
    required bool useScanArea,
  }) async {
    final croppedImagePath = await _createCroppedImageFile(
      imagePath,
      normalizedRoi: normalizedRoi,
      useScanArea: useScanArea,
    );
    if (croppedImagePath == null) return '';

    try {
      final textRecognizer = _textRecognizer ??= TextRecognizer();
      final recognizedText = await textRecognizer.processImage(
        InputImage.fromFilePath(croppedImagePath),
      );
      return recognizedText.text.trim();
    } finally {
      await _cleanupScanImage(croppedImagePath);
    }
  }

  Future<String?> _createCroppedImageFile(
    String imagePath, {
    required Rect? normalizedRoi,
    required bool useScanArea,
  }) async {
    final sourceBytes = await File(imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(sourceBytes);
    final frame = await codec.getNextFrame();
    final sourceImage = frame.image;
    final sourceWidth = sourceImage.width;
    final sourceHeight = sourceImage.height;
    final sourceSize = Size(sourceWidth.toDouble(), sourceHeight.toDouble());
    final roi = normalizedRoi != null
        ? _buildRoiFromNormalizedRect(
            size: sourceSize,
            normalizedRoi: normalizedRoi,
          )
        : useScanArea
        ? _buildScanRoi(sourceSize)
        : Offset.zero & sourceSize;
    final crop = _alignCropRect(roi, sourceWidth, sourceHeight);
    if (crop == null) {
      sourceImage.dispose();
      codec.dispose();
      return null;
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      sourceImage,
      Rect.fromLTWH(
        crop.left.toDouble(),
        crop.top.toDouble(),
        crop.width.toDouble(),
        crop.height.toDouble(),
      ),
      Rect.fromLTWH(0, 0, crop.width.toDouble(), crop.height.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    final picture = recorder.endRecording();
    ui.Image? croppedImage;

    try {
      croppedImage = await picture.toImage(crop.width, crop.height);
      final encoded = await croppedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (encoded == null) return null;

      final croppedPath = '${imagePath}_ocr_roi.png';
      await File(croppedPath).writeAsBytes(
        encoded.buffer.asUint8List(
          encoded.offsetInBytes,
          encoded.lengthInBytes,
        ),
        flush: true,
      );
      return croppedPath;
    } finally {
      croppedImage?.dispose();
      picture.dispose();
      sourceImage.dispose();
      codec.dispose();
    }
  }

  Rect _buildScanRoi(Size size) {
    var visibleWidthFactor = 1.0;
    var visibleHeightFactor = 1.0;
    final viewportAspectRatio = _scanViewportAspectRatio;
    final imageAspectRatio = size.width / size.height;

    if (viewportAspectRatio != null) {
      if (imageAspectRatio > viewportAspectRatio) {
        visibleWidthFactor = viewportAspectRatio / imageAspectRatio;
      } else if (imageAspectRatio < viewportAspectRatio) {
        visibleHeightFactor = imageAspectRatio / viewportAspectRatio;
      }
    }

    final width = size.width * scanAreaWidthFactor * visibleWidthFactor;
    final height = size.height * scanAreaHeightFactor * visibleHeightFactor;
    final left = (size.width - width) / 2;
    final top = (size.height - height) / 2;
    return Rect.fromLTWH(left, top, width, height);
  }

  Rect _buildRoiFromNormalizedRect({
    required Size size,
    required Rect normalizedRoi,
  }) {
    final left = (normalizedRoi.left).clamp(0.0, 1.0);
    final top = (normalizedRoi.top).clamp(0.0, 1.0);
    final right = (normalizedRoi.right).clamp(0.0, 1.0);
    final bottom = (normalizedRoi.bottom).clamp(0.0, 1.0);

    if (right <= left || bottom <= top) {
      return Rect.fromLTWH(0, 0, size.width, size.height);
    }

    return Rect.fromLTRB(
      size.width * left,
      size.height * top,
      size.width * right,
      size.height * bottom,
    );
  }

  bool _rectCenterInRoi(Rect rect, Rect roi) {
    final center = rect.center;
    return roi.contains(center);
  }

  bool _isOverBarcode(Rect lineRect, List<Barcode> barcodes) {
    for (final barcode in barcodes) {
      final barcodeRect = barcode.boundingBox;
      if (lineRect.overlaps(barcodeRect.inflate(6))) return true;
    }
    return false;
  }

  Future<void> _cleanupScanImage(String imagePath) async {
    try {
      final file = File(imagePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Ignore cleanup failures for temporary camera images.
    }
  }

  Future<void> releaseCamera() async {
    if (_disposed) return;
    _cameraSessionVersion += 1;
    await stopPackageLookupAutoScan();

    final controller = _cameraController;
    _cameraController = null;
    _activeCamera = null;
    _torchEnabled = false;
    _cameraPermissionDenied = false;
    _notifyCameraUi();

    if (controller != null) {
      try {
        await controller.dispose();
      } catch (_) {
        // The native camera may already be closing with the route.
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cameraSessionVersion += 1;
    _torchEnabled = false;
    _autoLookupActive = false;
    _autoLookupDetected = null;
    _forceNextAutoLookupFrame = false;
    _cameraController?.dispose();
    _textRecognizer?.close();
    _barcodeScanner?.close();
    _cameraTick.dispose();
    _scanTick.dispose();
    super.dispose();
  }
}
