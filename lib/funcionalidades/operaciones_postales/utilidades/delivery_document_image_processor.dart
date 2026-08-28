import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

class DeliveryDocumentImageProcessor {
  const DeliveryDocumentImageProcessor._();
  static const int documentProcessingMaxDimension = 1800;
  static const int _documentProcessingMaxDimension =
      documentProcessingMaxDimension;

  static Future<DeliveryDocumentRaster> decodeForEditing(
    Uint8List sourceBytes,
  ) async {
    final decoded = await _decodeRgba(
      sourceBytes,
      maxDimension: _documentProcessingMaxDimension,
    );
    return DeliveryDocumentRaster(
      rgba: decoded.rgba,
      width: decoded.width,
      height: decoded.height,
    );
  }

  static Future<Uint8List> buildCleanDocumentPngFromRaster(
    DeliveryDocumentRaster raster, {
    required List<ui.Offset> normalizedQuad,
  }) async {
    if (normalizedQuad.length != 4) {
      throw ArgumentError(
        'Se requieren exactamente 4 esquinas para ajustar la factura.',
      );
    }

    final width = raster.width.toDouble();
    final height = raster.height.toDouble();
    final quad = normalizedQuad
        .map(
          (point) => ui.Offset(
            (point.dx * width).clamp(0.0, width - 1),
            (point.dy * height).clamp(0.0, height - 1),
          ),
        )
        .toList(growable: false);
    final insetQuad = _scaledQuadAroundCenter(quad, 0.992);

    return _buildCleanDocumentPngFromDecoded(
      rgba: raster.rgba,
      width: raster.width,
      height: raster.height,
      quad: insetQuad,
    );
  }

  static Future<Uint8List> buildPreservedGrayscalePng(
    Uint8List sourceBytes,
  ) async {
    final decoded = await _decodeRgba(
      sourceBytes,
      maxDimension: _documentProcessingMaxDimension,
    );
    final rgba = decoded.rgba;
    final pixelCount = decoded.width * decoded.height;
    final luminances = Uint8List(pixelCount);
    final histogram = List<int>.filled(256, 0);

    for (
      var byteIndex = 0, pixelIndex = 0;
      byteIndex < rgba.length;
      byteIndex += 4, pixelIndex++
    ) {
      final red = rgba[byteIndex];
      final green = rgba[byteIndex + 1];
      final blue = rgba[byteIndex + 2];
      final alpha = rgba[byteIndex + 3];

      if (alpha == 0) {
        luminances[pixelIndex] = 255;
        histogram[255] += 1;
        continue;
      }

      final luma = ((red * 38) + (green * 75) + (blue * 15)) >> 7;
      luminances[pixelIndex] = luma;
      histogram[luma] += 1;
    }

    final blackPoint = _histogramPercentile(histogram, pixelCount, 0.01);
    final whitePoint = _histogramPercentile(histogram, pixelCount, 0.995);
    final toneLookup = _buildPreservedToneLookup(blackPoint, whitePoint);
    final output = Uint8List(rgba.length);

    for (
      var byteIndex = 0, pixelIndex = 0;
      byteIndex < output.length;
      byteIndex += 4, pixelIndex++
    ) {
      final tone = toneLookup[luminances[pixelIndex]];
      output[byteIndex] = tone;
      output[byteIndex + 1] = tone;
      output[byteIndex + 2] = tone;
      output[byteIndex + 3] = 0xFF;
    }

    return _encodePng(output, decoded.width, decoded.height);
  }

  static Future<Uint8List> buildSoftGrayscalePng(Uint8List sourceBytes) async {
    final decoded = await _decodeRgba(
      sourceBytes,
      maxDimension: _documentProcessingMaxDimension,
    );
    final rgba = decoded.rgba;
    final pixelCount = decoded.width * decoded.height;
    final luminances = Uint8List(pixelCount);

    for (
      var byteIndex = 0, pixelIndex = 0;
      byteIndex < rgba.length;
      byteIndex += 4, pixelIndex++
    ) {
      final red = rgba[byteIndex];
      final green = rgba[byteIndex + 1];
      final blue = rgba[byteIndex + 2];
      final alpha = rgba[byteIndex + 3];

      if (alpha == 0) {
        luminances[pixelIndex] = 255;
        continue;
      }

      final luma = ((red * 38) + (green * 75) + (blue * 15)) >> 7;
      luminances[pixelIndex] = luma;
    }

    final sharpenedLuminances = _sharpenLuminance(
      luminances,
      decoded.width,
      decoded.height,
    );
    final sharpenedHistogram = _buildHistogram(sharpenedLuminances);

    final blackPoint = _histogramPercentile(
      sharpenedHistogram,
      pixelCount,
      0.015,
    );
    final whitePoint = _histogramPercentile(
      sharpenedHistogram,
      pixelCount,
      0.99,
    );
    final threshold = _otsuThreshold(sharpenedHistogram);
    final normalizedThreshold = _normalizeLuminance(
      threshold,
      blackPoint,
      whitePoint,
    ).clamp(92, 188);
    final toneLookup = _buildDocumentGrayToneLookup(
      blackPoint,
      whitePoint,
      normalizedThreshold,
    );

    final output = Uint8List(rgba.length);
    for (
      var byteIndex = 0, pixelIndex = 0;
      byteIndex < output.length;
      byteIndex += 4, pixelIndex++
    ) {
      final tone = toneLookup[sharpenedLuminances[pixelIndex]];
      output[byteIndex] = tone;
      output[byteIndex + 1] = tone;
      output[byteIndex + 2] = tone;
      output[byteIndex + 3] = 0xFF;
    }

    return _encodePng(output, decoded.width, decoded.height);
  }

  static Future<Uint8List> rotateToPng(
    Uint8List sourceBytes, {
    required int quarterTurns,
  }) async {
    final normalizedTurns = quarterTurns % 4;
    if (normalizedTurns == 0) {
      final decoded = await _decodeRgba(sourceBytes);
      return _encodePng(decoded.rgba, decoded.width, decoded.height);
    }

    final decoded = await _decodeRgba(sourceBytes);
    final sourceWidth = decoded.width;
    final sourceHeight = decoded.height;
    final rotatedWidth = normalizedTurns.isOdd ? sourceHeight : sourceWidth;
    final rotatedHeight = normalizedTurns.isOdd ? sourceWidth : sourceHeight;
    final output = Uint8List(rotatedWidth * rotatedHeight * 4);

    for (var y = 0; y < sourceHeight; y++) {
      for (var x = 0; x < sourceWidth; x++) {
        final srcOffset = ((y * sourceWidth) + x) * 4;
        late final int targetX;
        late final int targetY;

        switch (normalizedTurns) {
          case 1:
            targetX = sourceHeight - 1 - y;
            targetY = x;
            break;
          case 2:
            targetX = sourceWidth - 1 - x;
            targetY = sourceHeight - 1 - y;
            break;
          case 3:
            targetX = y;
            targetY = sourceWidth - 1 - x;
            break;
          default:
            targetX = x;
            targetY = y;
        }

        final dstOffset = ((targetY * rotatedWidth) + targetX) * 4;
        output[dstOffset] = decoded.rgba[srcOffset];
        output[dstOffset + 1] = decoded.rgba[srcOffset + 1];
        output[dstOffset + 2] = decoded.rgba[srcOffset + 2];
        output[dstOffset + 3] = decoded.rgba[srcOffset + 3];
      }
    }

    return _encodePng(output, rotatedWidth, rotatedHeight);
  }

  static Uint8List _buildPreservedToneLookup(int blackPoint, int whitePoint) {
    final lookup = Uint8List(256);
    for (var value = 0; value < lookup.length; value++) {
      final normalized = _normalizeLuminance(value, blackPoint, whitePoint);
      lookup[value] = _preserveDocumentToneFor(normalized);
    }
    return lookup;
  }

  static Uint8List _buildDocumentGrayToneLookup(
    int blackPoint,
    int whitePoint,
    int normalizedThreshold,
  ) {
    final lookup = Uint8List(256);
    for (var value = 0; value < lookup.length; value++) {
      final normalized = _normalizeLuminance(value, blackPoint, whitePoint);
      lookup[value] = _documentGrayToneFor(normalized, normalizedThreshold);
    }
    return lookup;
  }

  static Future<_DecodedImage> _decodeRgba(
    Uint8List sourceBytes, {
    int? maxDimension,
  }) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(sourceBytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;

    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final targetSize = _scaledDimensionsFor(
        descriptor.width,
        descriptor.height,
        maxDimension,
      );
      codec = await descriptor.instantiateCodec(
        targetWidth: targetSize?.width,
        targetHeight: targetSize?.height,
      );
      final frame = await codec.getNextFrame();
      image = frame.image;
      final rawBytes = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (rawBytes == null) {
        throw StateError('No se pudo leer la imagen escaneada.');
      }

      return _DecodedImage(
        rgba: rawBytes.buffer.asUint8List(),
        width: image.width,
        height: image.height,
      );
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  static Future<Uint8List> _encodePng(
    Uint8List rgbaBytes,
    int width,
    int height,
  ) async {
    final processedImage = await _imageFromRgba(rgbaBytes, width, height);
    try {
      final pngBytes = await processedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (pngBytes == null) {
        throw StateError('No se pudo preparar la factura.');
      }
      return pngBytes.buffer.asUint8List(
        pngBytes.offsetInBytes,
        pngBytes.lengthInBytes,
      );
    } finally {
      processedImage.dispose();
    }
  }

  static int _histogramPercentile(
    List<int> histogram,
    int totalPixels,
    double percentile,
  ) {
    final target = math.max(1, (totalPixels * percentile).round());
    var seen = 0;
    for (var value = 0; value < histogram.length; value++) {
      seen += histogram[value];
      if (seen >= target) {
        return value;
      }
    }
    return 255;
  }

  static int _otsuThreshold(List<int> histogram) {
    var total = 0;
    var weightedSum = 0;
    for (var value = 0; value < histogram.length; value++) {
      final count = histogram[value];
      total += count;
      weightedSum += value * count;
    }

    var sumBackground = 0;
    var weightBackground = 0;
    var bestThreshold = 128;
    var bestVariance = -1.0;

    for (var value = 0; value < histogram.length; value++) {
      final count = histogram[value];
      weightBackground += count;
      if (weightBackground == 0) {
        continue;
      }

      final weightForeground = total - weightBackground;
      if (weightForeground == 0) {
        break;
      }

      sumBackground += value * count;
      final meanBackground = sumBackground / weightBackground;
      final meanForeground = (weightedSum - sumBackground) / weightForeground;
      final delta = meanBackground - meanForeground;
      final variance = weightBackground * weightForeground * delta * delta;
      if (variance > bestVariance) {
        bestVariance = variance;
        bestThreshold = value;
      }
    }

    return bestThreshold;
  }

  static int _normalizeLuminance(int value, int blackPoint, int whitePoint) {
    final range = math.max(whitePoint - blackPoint, 24);
    final normalized = ((value - blackPoint) * 255 / range).round();
    return normalized.clamp(0, 255);
  }

  static Future<Uint8List> _buildCleanDocumentPngFromDecoded({
    required Uint8List rgba,
    required int width,
    required int height,
    required List<ui.Offset> quad,
  }) async {
    final targetWidth = math.max(
      48,
      (((quad[1] - quad[0]).distance + (quad[2] - quad[3]).distance) / 2)
          .round(),
    );
    final targetHeight = math.max(
      48,
      (((quad[3] - quad[0]).distance + (quad[2] - quad[1]).distance) / 2)
          .round(),
    );
    final pixelCount = targetWidth * targetHeight;
    final output = Uint8List(pixelCount * 4);

    for (var y = 0; y < targetHeight; y++) {
      final v = targetHeight <= 1 ? 0.0 : y / (targetHeight - 1);
      final left = ui.Offset.lerp(quad[0], quad[3], v)!;
      final right = ui.Offset.lerp(quad[1], quad[2], v)!;
      final rowOffset = y * targetWidth;

      for (var x = 0; x < targetWidth; x++) {
        final u = targetWidth <= 1 ? 0.0 : x / (targetWidth - 1);
        final sample = ui.Offset.lerp(left, right, u)!;
        final pixelIndex = rowOffset + x;
        final dstOffset = pixelIndex * 4;

        _sampleRgbaBilinear(
          rgba,
          width,
          height,
          sample.dx,
          sample.dy,
          output,
          dstOffset,
        );
      }
    }

    return _encodePng(output, targetWidth, targetHeight);
  }

  static void _sampleRgbaBilinear(
    Uint8List rgba,
    int width,
    int height,
    double x,
    double y,
    Uint8List output,
    int dstOffset,
  ) {
    final clampedX = x.clamp(0.0, width - 1.0);
    final clampedY = y.clamp(0.0, height - 1.0);
    final x0 = clampedX.floor();
    final y0 = clampedY.floor();
    final x1 = math.min(x0 + 1, width - 1);
    final y1 = math.min(y0 + 1, height - 1);
    final tx = clampedX - x0;
    final ty = clampedY - y0;

    final offset00 = ((y0 * width) + x0) * 4;
    final offset10 = ((y0 * width) + x1) * 4;
    final offset01 = ((y1 * width) + x0) * 4;
    final offset11 = ((y1 * width) + x1) * 4;

    for (var channel = 0; channel < 4; channel++) {
      final c00 = rgba[offset00 + channel];
      final c10 = rgba[offset10 + channel];
      final c01 = rgba[offset01 + channel];
      final c11 = rgba[offset11 + channel];

      final top = c00 + ((c10 - c00) * tx);
      final bottom = c01 + ((c11 - c01) * tx);
      final value = (top + ((bottom - top) * ty)).round().clamp(0, 255);
      output[dstOffset + channel] = value;
    }
  }

  static List<int> _buildHistogram(Uint8List luminances) {
    final histogram = List<int>.filled(256, 0);
    for (final luminance in luminances) {
      histogram[luminance] += 1;
    }
    return histogram;
  }

  static Uint8List _sharpenLuminance(
    Uint8List luminances,
    int width,
    int height,
  ) {
    if (width < 3 || height < 3) {
      return Uint8List.fromList(luminances);
    }

    final output = Uint8List.fromList(luminances);
    for (var y = 1; y < height - 1; y++) {
      final rowOffset = y * width;
      for (var x = 1; x < width - 1; x++) {
        final index = rowOffset + x;
        final center = luminances[index];
        final neighbors =
            luminances[index - 1] +
            luminances[index + 1] +
            luminances[index - width] +
            luminances[index + width];
        final detail = (center * 4) - neighbors;
        final sharpened = center + ((detail * 5) ~/ 32);
        output[index] = sharpened.clamp(0, 255);
      }
    }

    return output;
  }

  static int _documentGrayToneFor(int value, int threshold) {
    final centered = value - threshold;
    final contrasted = (150 + (centered * 0.72)).round().clamp(0, 255);
    final blended = ((value * 0.62) + (contrasted * 0.38)).round().clamp(
      0,
      255,
    );

    if (blended >= 220) {
      return math.min(246, blended + 2);
    }
    if (blended <= 60) {
      return math.max(24, blended - 3);
    }
    return blended;
  }

  static int _preserveDocumentToneFor(int value) {
    final lifted = ((value * 236) ~/ 255) + 10;
    final centered = lifted - 128;
    final contrasted = (((centered * 108) ~/ 100) + 128).clamp(6, 250);
    return contrasted;
  }

  static _ScaledDimensions? _scaledDimensionsFor(
    int width,
    int height,
    int? maxDimension,
  ) {
    if (maxDimension == null) {
      return null;
    }

    final longestSide = math.max(width, height);
    if (longestSide <= maxDimension) {
      return null;
    }

    final scale = maxDimension / longestSide;
    return _ScaledDimensions(
      width: math.max(1, (width * scale).round()),
      height: math.max(1, (height * scale).round()),
    );
  }

  static List<ui.Offset> _scaledQuadAroundCenter(
    List<ui.Offset> quad,
    double factor,
  ) {
    var centerX = 0.0;
    var centerY = 0.0;
    for (final point in quad) {
      centerX += point.dx;
      centerY += point.dy;
    }

    final centroid = ui.Offset(centerX / quad.length, centerY / quad.length);
    return quad
        .map((point) => centroid + ((point - centroid) * factor))
        .toList(growable: false);
  }

  static Future<ui.Image> _imageFromRgba(
    Uint8List rgbaBytes,
    int width,
    int height,
  ) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgbaBytes,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }
}

class _DecodedImage {
  const _DecodedImage({
    required this.rgba,
    required this.width,
    required this.height,
  });

  final Uint8List rgba;
  final int width;
  final int height;
}

class _ScaledDimensions {
  const _ScaledDimensions({required this.width, required this.height});

  final int width;
  final int height;
}

class DeliveryDocumentRaster {
  const DeliveryDocumentRaster({
    required this.rgba,
    required this.width,
    required this.height,
  });

  final Uint8List rgba;
  final int width;
  final int height;
}
