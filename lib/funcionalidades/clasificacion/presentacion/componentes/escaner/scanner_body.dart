import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'package:scan_agbc/nucleo/componentes/app_cards.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/presentacion/controladores/scanner_controller.dart';
import 'package:scan_agbc/nucleo/tema/app_theme.dart';

class ScannerBody extends StatelessWidget {
  const ScannerBody({
    super.key,
    required this.controller,
    required this.lineAnimation,
    required this.onScanFromCamera,
    required this.onScanFromGallery,
    required this.onShowRecentCodes,
    this.packageLookupMode = false,
    this.packageRecognitionMode = PackageLookupRecognitionMode.barcode,
    this.onPackageRecognitionModeChanged,
    this.selectedPackageCount = 0,
    this.onReviewSelectedPackages,
  });

  final ScannerController controller;
  final Animation<double> lineAnimation;
  final Future<void> Function() onScanFromCamera;
  final Future<void> Function() onScanFromGallery;
  final Future<void> Function() onShowRecentCodes;
  final bool packageLookupMode;
  final PackageLookupRecognitionMode packageRecognitionMode;
  final ValueChanged<PackageLookupRecognitionMode>?
  onPackageRecognitionModeChanged;
  final int selectedPackageCount;
  final Future<void> Function()? onReviewSelectedPackages;

  static const double _actionsBottomInset = 14.0;
  static const double _actionsOuterPadding = 16.0;
  static const double _actionsInnerPadding = 10.0;
  static const double _actionsVerticalGap = 12.0;
  static const double _actionButtonHeight = 72.0;
  static const double _actionsEstimatedHeight =
      _actionsInnerPadding * 2 + _actionButtonHeight;

  double _hintBottomInset(BuildContext context) {
    final safeBottom = MediaQuery.of(context).viewPadding.bottom;
    final bottom =
        safeBottom +
        _actionsBottomInset +
        _actionsOuterPadding +
        _actionsEstimatedHeight +
        _actionsVerticalGap;
    final maxInset = MediaQuery.of(context).size.height * 0.42;
    return bottom.clamp(108.0, maxInset);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        controller.cameraListenable,
        controller.scanListenable,
      ]),
      builder: (context, _) {
        final safeBottom = MediaQuery.of(context).viewPadding.bottom;
        return Stack(
          fit: StackFit.expand,
          children: [
            _CameraPreviewCard(
              controller: controller,
              lineAnimation: lineAnimation,
              onScan: onScanFromCamera,
              fullScreen: true,
              packageLookupMode: packageLookupMode,
              packageRecognitionMode: packageRecognitionMode,
              onPackageRecognitionModeChanged: onPackageRecognitionModeChanged,
            ),
            if (!packageLookupMode &&
                !controller.cameraReady &&
                !controller.initializingCamera)
              _SwipeHintOverlay(bottomInset: _hintBottomInset(context)),
            Positioned(
              left: 16,
              right: 16,
              bottom: 14 + safeBottom,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: packageLookupMode ? 620 : 560,
                  ),
                  child: AppActionTray(
                    child: _ScanActionsBar(
                      controller: controller,
                      onScanFromCamera: onScanFromCamera,
                      onScanFromGallery: onScanFromGallery,
                      onShowRecentCodes: onShowRecentCodes,
                      packageLookupMode: packageLookupMode,
                      selectedPackageCount: selectedPackageCount,
                      onReviewSelectedPackages: onReviewSelectedPackages,
                      embedded: true,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CameraPreviewCard extends StatelessWidget {
  const _CameraPreviewCard({
    required this.controller,
    required this.lineAnimation,
    required this.onScan,
    this.fullScreen = false,
    this.packageLookupMode = false,
    this.packageRecognitionMode = PackageLookupRecognitionMode.barcode,
    this.onPackageRecognitionModeChanged,
  });

  final ScannerController controller;
  final Animation<double> lineAnimation;
  final Future<void> Function() onScan;
  final bool fullScreen;
  final bool packageLookupMode;
  final PackageLookupRecognitionMode packageRecognitionMode;
  final ValueChanged<PackageLookupRecognitionMode>?
  onPackageRecognitionModeChanged;

  Future<void> _handlePreviewTap() async {
    if (controller.isProcessing) return;
    await onScan();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        controller.cameraListenable,
        controller.scanListenable,
      ]),
      builder: (context, _) {
        final content = GestureDetector(
          onTap: _handlePreviewTap,
          onVerticalDragEnd: (details) async {
            if (controller.cameraReady || controller.initializingCamera) return;
            final velocity = details.primaryVelocity ?? 0;
            if (velocity < -800) {
              await controller.initCamera();
            }
          },
          behavior: HitTestBehavior.opaque,
          child: Container(
            decoration: fullScreen
                ? (controller.cameraReady
                      ? const BoxDecoration(
                          color: Color.fromRGBO(255, 254, 254, 0.84),
                        )
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
                        ))
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.yellow, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x331B305F),
                        blurRadius: 16,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
            child: ClipRRect(
              borderRadius: fullScreen
                  ? BorderRadius.zero
                  : BorderRadius.circular(4),
              child: RepaintBoundary(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final previewViewport = _resolvePreviewViewport(
                      constraints.biggest,
                    );

                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildCameraLayer(
                          controller,
                          previewViewport.cameraRect,
                        ),
                        if (controller.cameraReady)
                          _ScannerOverlay(
                            progress: lineAnimation,
                            showAnimation:
                                controller.cameraReady &&
                                !controller.initializingCamera,
                            widthFactor: controller.scanAreaWidthFactor,
                            heightFactor: controller.scanAreaHeightFactor,
                            previewRect: previewViewport.overlayRect,
                          ),
                        if (packageLookupMode &&
                            onPackageRecognitionModeChanged != null)
                          _PackageRecognitionModeSelectorPositioned(
                            previewRect: previewViewport.overlayRect,
                            scanAreaHeightFactor:
                                controller.scanAreaHeightFactor,
                            selectedMode: packageRecognitionMode,
                            onChanged: onPackageRecognitionModeChanged!,
                          ),
                        _LogoOverlay(cameraReady: controller.cameraReady),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );

        if (fullScreen) return content;
        final size = MediaQuery.of(context).size;
        final rawAspect =
            controller.cameraController?.value.aspectRatio ?? (16 / 9);
        final previewAspect = rawAspect > 1 ? (1 / rawAspect) : rawAspect;
        final previewHeight = ((size.width - 32) / previewAspect).clamp(
          220.0,
          size.height * 0.7,
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: SizedBox(
            height: previewHeight,
            width: double.infinity,
            child: content,
          ),
        );
      },
    );
  }

  _PreviewViewport _resolvePreviewViewport(Size availableSize) {
    final previewAspect = _cameraPreviewAspectRatio(controller);
    if (fullScreen) {
      return _PreviewViewport(
        cameraRect: _buildCoverViewportRect(availableSize, previewAspect),
        overlayRect: Offset.zero & availableSize,
      );
    }

    final containedRect = _buildContainedViewportRect(
      availableSize,
      previewAspect,
    );
    return _PreviewViewport(
      cameraRect: containedRect,
      overlayRect: containedRect,
    );
  }

  Widget _buildCameraLayer(ScannerController controller, Rect previewRect) {
    if (controller.initializingCamera) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.cameraReady) {
      final cameraController = controller.cameraController!;
      return Positioned.fromRect(
        rect: previewRect,
        child: ClipRRect(
          borderRadius: fullScreen
              ? BorderRadius.zero
              : BorderRadius.circular(4),
          child: CameraPreview(cameraController),
        ),
      );
    }
    return const SizedBox.expand();
  }
}

class _PackageRecognitionModeSelectorPositioned extends StatelessWidget {
  const _PackageRecognitionModeSelectorPositioned({
    required this.previewRect,
    required this.scanAreaHeightFactor,
    required this.selectedMode,
    required this.onChanged,
  });

  final Rect previewRect;
  final double scanAreaHeightFactor;
  final PackageLookupRecognitionMode selectedMode;
  final ValueChanged<PackageLookupRecognitionMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final scanAreaBottom =
        previewRect.top + (previewRect.height * (1 + scanAreaHeightFactor) / 2);
    final maxTop = (previewRect.bottom - 176).clamp(96.0, double.infinity);
    final selectorTop = (scanAreaBottom + 18).clamp(96.0, maxTop).toDouble();

    return Positioned(
      top: selectorTop,
      left: 0,
      right: 0,
      child: Center(
        child: _PackageRecognitionModeSelector(
          selectedMode: selectedMode,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _PackageRecognitionModeSelector extends StatelessWidget {
  const _PackageRecognitionModeSelector({
    required this.selectedMode,
    required this.onChanged,
  });

  final PackageLookupRecognitionMode selectedMode;
  final ValueChanged<PackageLookupRecognitionMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF7EDCF),
      elevation: 8,
      shadowColor: const Color(0x661B305F),
      shape: const StadiumBorder(
        side: BorderSide(color: AppTheme.yellow, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 258,
        height: 58,
        child: Row(
          children: [
            Expanded(
              child: _PackageRecognitionModeOption(
                icon: Icons.view_week_rounded,
                label: 'Barras',
                selected: selectedMode == PackageLookupRecognitionMode.barcode,
                onTap: () => onChanged(PackageLookupRecognitionMode.barcode),
              ),
            ),
            Container(
              width: 1,
              height: double.infinity,
              color: AppTheme.blueDark.withValues(alpha: 0.12),
            ),
            Expanded(
              child: _PackageRecognitionModeOption(
                icon: Icons.document_scanner_outlined,
                label: 'Texto OCR',
                selected: selectedMode == PackageLookupRecognitionMode.ocr,
                onTap: () => onChanged(PackageLookupRecognitionMode.ocr),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PackageRecognitionModeOption extends StatelessWidget {
  const _PackageRecognitionModeOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeColor = AppTheme.blueDark;
    final inactiveColor = AppTheme.blueDark.withValues(alpha: 0.38);
    final iconColor = selected ? activeColor : inactiveColor;
    final textColor = selected ? activeColor : inactiveColor;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        height: double.infinity,
        alignment: Alignment.center,
        color: selected ? AppTheme.actionYellowStrong : Colors.transparent,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwipeHintOverlay extends StatelessWidget {
  const _SwipeHintOverlay({required this.bottomInset});

  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SwipeArrowHint(),
              SizedBox(height: 8),
              _SwipeHintBubble(),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwipeHintBubble extends StatefulWidget {
  const _SwipeHintBubble();

  @override
  State<_SwipeHintBubble> createState() => _SwipeHintBubbleState();
}

class _SwipeHintBubbleState extends State<_SwipeHintBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _offset = Tween<double>(
      begin: 8,
      end: 0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Transform.translate(
          offset: Offset(0, -_offset.value),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xCCFFF1CF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x661B305F)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x331B305F),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.swipe_up_rounded, color: AppTheme.blue, size: 16),
                SizedBox(width: 6),
                Text(
                  'Desliza hacia arriba para activar la cámara',
                  style: TextStyle(
                    color: AppTheme.blue,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    height: 1.05,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SwipeArrowHint extends StatefulWidget {
  const _SwipeArrowHint();

  @override
  State<_SwipeArrowHint> createState() => _SwipeArrowHintState();
}

class _SwipeArrowHintState extends State<_SwipeArrowHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _offset;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _offset = Tween<double>(
      begin: 10,
      end: -2,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _opacity = Tween<double>(
      begin: 0.35,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Opacity(
          opacity: _opacity.value,
          child: Transform.translate(
            offset: Offset(0, -_offset.value),
            child: const Icon(
              Icons.expand_less_rounded,
              color: AppTheme.blue,
              size: 28,
            ),
          ),
        );
      },
    );
  }
}

class _PreviewViewport {
  const _PreviewViewport({required this.cameraRect, required this.overlayRect});

  final Rect cameraRect;
  final Rect overlayRect;
}

double _cameraPreviewAspectRatio(ScannerController controller) {
  final rawAspect = controller.cameraController?.value.aspectRatio ?? (16 / 9);
  return rawAspect > 1 ? (1 / rawAspect) : rawAspect;
}

Rect _buildContainedViewportRect(
  Size containerSize,
  double contentAspectRatio,
) {
  final containerAspectRatio =
      containerSize.width / containerSize.height.clamp(1.0, double.infinity);

  late final double contentWidth;
  late final double contentHeight;

  if (contentAspectRatio > containerAspectRatio) {
    contentWidth = containerSize.width;
    contentHeight = contentWidth / contentAspectRatio;
  } else {
    contentHeight = containerSize.height;
    contentWidth = contentHeight * contentAspectRatio;
  }

  final left = (containerSize.width - contentWidth) / 2;
  final top = (containerSize.height - contentHeight) / 2;
  return Rect.fromLTWH(left, top, contentWidth, contentHeight);
}

Rect _buildCoverViewportRect(Size containerSize, double contentAspectRatio) {
  final containerAspectRatio =
      containerSize.width / containerSize.height.clamp(1.0, double.infinity);

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

class _ScanActionsBar extends StatelessWidget {
  const _ScanActionsBar({
    required this.controller,
    required this.onScanFromCamera,
    required this.onScanFromGallery,
    required this.onShowRecentCodes,
    required this.packageLookupMode,
    required this.selectedPackageCount,
    required this.onReviewSelectedPackages,
    this.embedded = false,
  });

  final ScannerController controller;
  final Future<void> Function() onScanFromCamera;
  final Future<void> Function() onScanFromGallery;
  final Future<void> Function() onShowRecentCodes;
  final bool packageLookupMode;
  final int selectedPackageCount;
  final Future<void> Function()? onReviewSelectedPackages;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        controller.cameraListenable,
        controller.scanListenable,
      ]),
      builder: (context, _) {
        final actionsRow = Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _ScanActionButton(
              icon: Icons.photo_library_outlined,
              tooltip: 'Galeria',
              compact: true,
              onPressed: controller.isProcessing ? null : onScanFromGallery,
            ),
            _ScanActionButton.primary(
              icon: controller.isProcessing
                  ? Icons.autorenew_rounded
                  : Icons.camera_alt_rounded,
              tooltip: controller.isProcessing
                  ? 'Escaneando'
                  : packageLookupMode
                  ? (controller.cameraReady
                        ? 'Buscar ahora'
                        : 'Activa la cámara')
                  : (controller.cameraReady
                        ? 'Escanear ahora'
                        : 'Activa la cámara'),
              onPressed: controller.isProcessing ? null : onScanFromCamera,
            ),
            if (packageLookupMode)
              onReviewSelectedPackages == null
                  ? const SizedBox(width: 59)
                  : Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _ScanActionButton.confirm(
                          icon: Icons.playlist_add_check_rounded,
                          tooltip: 'Revisar seleccionados',
                          compact: true,
                          onPressed: selectedPackageCount == 0
                              ? null
                              : onReviewSelectedPackages,
                        ),
                        if (selectedPackageCount > 0)
                          Positioned(
                            top: -6,
                            right: -5,
                            child: Container(
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppTheme.errorRed,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: AppTheme.yellowLight,
                                  width: 2,
                                ),
                              ),
                              child: Text(
                                selectedPackageCount > 99
                                    ? '99+'
                                    : '$selectedPackageCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                      ],
                    )
            else
              _ScanActionButton.confirm(
                icon: Icons.list_alt_rounded,
                tooltip: 'Últimos códigos',
                compact: true,
                onPressed: onShowRecentCodes,
              ),
          ],
        );

        if (embedded) return actionsRow;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: actionsRow,
        );
      },
    );
  }
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay({
    required this.progress,
    required this.showAnimation,
    required this.widthFactor,
    required this.heightFactor,
    required this.previewRect,
  });

  final Animation<double> progress;
  final bool showAnimation;
  final double widthFactor;
  final double heightFactor;
  final Rect previewRect;

  @override
  Widget build(BuildContext context) {
    final areaWidth = previewRect.width * widthFactor;
    final areaHeight = previewRect.height * heightFactor;
    final areaLeft = previewRect.left + ((previewRect.width - areaWidth) / 2);
    final areaTop = previewRect.top + ((previewRect.height - areaHeight) / 2);
    final cornerSize = (areaWidth * 0.16).clamp(54.0, 78.0).toDouble();
    final roiRect = Rect.fromLTWH(areaLeft, areaTop, areaWidth, areaHeight);

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _OutsideRoiMaskPainter(
                previewRect: previewRect,
                roiRect: roiRect,
                overlayOpacity: showAnimation ? 0.68 : 0.90,
              ),
            ),
          ),
        ),
        Positioned(
          left: areaLeft,
          top: areaTop,
          width: areaWidth,
          height: areaHeight,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.overlayBorder, width: 1.7),
                borderRadius: BorderRadius.circular(18),
                color: const Color(0x0E1B305F),
              ),
            ),
          ),
        ),
        _CornerMarker(
          left: areaLeft,
          top: areaTop,
          isLeft: true,
          isTop: true,
          size: cornerSize,
        ),
        _CornerMarker(
          left: areaLeft + areaWidth - cornerSize,
          top: areaTop,
          isLeft: false,
          isTop: true,
          size: cornerSize,
        ),
        _CornerMarker(
          left: areaLeft,
          top: areaTop + areaHeight - cornerSize,
          isLeft: true,
          isTop: false,
          size: cornerSize,
        ),
        _CornerMarker(
          left: areaLeft + areaWidth - cornerSize,
          top: areaTop + areaHeight - cornerSize,
          isLeft: false,
          isTop: false,
          size: cornerSize,
        ),
        if (showAnimation)
          AnimatedBuilder(
            animation: progress,
            builder: (context, _) {
              final scanY = areaTop + (areaHeight - 2) * progress.value;
              return Positioned(
                left: areaLeft + 10,
                top: scanY,
                width: areaWidth - 20,
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
              );
            },
          ),
      ],
    );
  }
}

class _LogoOverlay extends StatelessWidget {
  const _LogoOverlay({required this.cameraReady});

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

class _ScanActionButton extends StatelessWidget {
  const _ScanActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.compact = false,
  }) : _primary = false,
       _confirm = false;

  const _ScanActionButton.primary({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  }) : compact = false,
       _primary = true,
       _confirm = false;

  const _ScanActionButton.confirm({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.compact = false,
  }) : _primary = false,
       _confirm = true;

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool compact;
  final bool _primary;
  final bool _confirm;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;
    final isConfirmActive = _confirm && isEnabled;
    final foregroundColor = isConfirmActive ? Colors.white : AppTheme.blueDark;
    final backgroundColor = isConfirmActive
        ? AppTheme.confirmBlue
        : _primary
        ? AppTheme.actionYellowStrong
        : AppTheme.actionSurfaceSoft;
    final borderColor = _confirm
        ? (isEnabled ? AppTheme.confirmBlueDark : const Color(0x6688AEDD))
        : AppTheme.strongBorder;
    final buttonStyle = OutlinedButton.styleFrom(
      foregroundColor: foregroundColor,
      disabledForegroundColor: _confirm
          ? const Color(0x99708AB5)
          : const Color(0x99627BA8),
      side: BorderSide(color: borderColor, width: _primary ? 2.1 : 1.5),
      backgroundColor: backgroundColor,
      disabledBackgroundColor: _confirm
          ? const Color(0x99D6E3F7)
          : const Color(0x99EFE5CB),
      shape: const CircleBorder(),
      padding: EdgeInsets.all(_primary ? 22 : (compact ? 16 : 19)),
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
          child: Icon(icon, size: _primary ? 32 : (compact ? 24 : 27)),
        ),
      ),
    );
  }
}

class _OutsideRoiMaskPainter extends CustomPainter {
  const _OutsideRoiMaskPainter({
    required this.previewRect,
    required this.roiRect,
    required this.overlayOpacity,
  });

  final Rect previewRect;
  final Rect roiRect;
  final double overlayOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppTheme.yellowLight.withValues(alpha: overlayOpacity),
          AppTheme.orangeWarm.withValues(alpha: overlayOpacity),
        ],
      ).createShader(previewRect);
    final clearPaint = Paint()..blendMode = BlendMode.clear;
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(previewRect, overlayPaint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(roiRect, const Radius.circular(18)),
      clearPaint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OutsideRoiMaskPainter oldDelegate) {
    return oldDelegate.previewRect != previewRect ||
        oldDelegate.roiRect != roiRect ||
        oldDelegate.overlayOpacity != overlayOpacity;
  }
}
