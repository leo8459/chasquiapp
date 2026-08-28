import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:scan_agbc/nucleo/tema/app_theme.dart';
import 'package:scan_agbc/nucleo/componentes/app_cards.dart';

class PackageTrackingSearchCard extends StatelessWidget {
  const PackageTrackingSearchCard({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.loading,
    required this.onSearch,
    required this.onPasteCode,
    this.title = 'Codigo del Paquete',
    this.hintText = 'Ejemplo: RR700000001BO',
    this.buttonLabel = 'Consultar paquetes',
    this.loadingLabel = 'Consultando...',
    this.helperText,
    this.onScanWithCamera,
    this.maxCodeLength = 20,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool loading;
  final Future<void> Function() onSearch;
  final Future<void> Function() onPasteCode;
  final String title;
  final String hintText;
  final String buttonLabel;
  final String loadingLabel;
  final String? helperText;
  final Future<void> Function()? onScanWithCamera;
  final int maxCodeLength;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AppPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.qr_code_2_rounded,
                color: AppTheme.blue,
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: textTheme.titleLarge)),
            ],
          ),
          if (helperText != null) ...[
            const SizedBox(height: 8),
            Text(helperText!, style: textTheme.bodyMedium),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            focusNode: focusNode,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSearch(),
            enableInteractiveSelection: true,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              LengthLimitingTextInputFormatter(maxCodeLength),
            ],
            decoration: InputDecoration(
              hintText: hintText,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                tooltip: 'Pegar código',
                onPressed: loading ? null : onPasteCode,
                icon: const Icon(Icons.content_paste_rounded),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: loading ? null : onSearch,
                  icon: loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: AppTheme.yellowField,
                          ),
                        )
                      : const Icon(Icons.search_rounded),
                  label: Text(loading ? loadingLabel : buttonLabel),
                ),
              ),
              if (onScanWithCamera != null) ...[
                const SizedBox(width: 10),
                _ScanCameraButton(
                  enabled: !loading,
                  onPressed: onScanWithCamera!,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class PackageTrackingQuickSearchBar extends StatelessWidget {
  const PackageTrackingQuickSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.loading,
    required this.onSearch,
    required this.onScanWithCamera,
    this.hintText = 'Buscar paquetes',
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool loading;
  final Future<void> Function() onSearch;
  final Future<void> Function()? onScanWithCamera;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 58,
            decoration: BoxDecoration(
              color: AppTheme.blueDark,
              borderRadius: AppTheme.radiusPill,
              border: Border.all(
                color: AppTheme.blue.withValues(alpha: 0.28),
                width: AppTheme.borderWidth,
              ),
              boxShadow: const [
                BoxShadow(
                  color: AppTheme.softShadow,
                  blurRadius: 14,
                  offset: Offset(0, 7),
                ),
              ],
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 58,
                  child: loading
                      ? const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: AppTheme.yellow,
                            ),
                          ),
                        )
                      : IconButton(
                          tooltip: 'Buscar',
                          onPressed: onSearch,
                          icon: const Icon(
                            Icons.search_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                ),
                Container(
                  width: 1.5,
                  height: 32,
                  color: Colors.white.withValues(alpha: 0.18),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      textSelectionTheme: const TextSelectionThemeData(
                        cursorColor: Colors.white,
                        selectionColor: Colors.white30,
                        selectionHandleColor: Colors.white,
                      ),
                    ),
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      enabled: !loading,
                      textInputAction: TextInputAction.search,
                      textCapitalization: TextCapitalization.characters,
                      keyboardType: TextInputType.text,
                      autocorrect: false,
                      enableSuggestions: false,
                      smartDashesType: SmartDashesType.disabled,
                      smartQuotesType: SmartQuotesType.disabled,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[A-Za-z0-9]'),
                        ),
                        LengthLimitingTextInputFormatter(20),
                      ],
                      onSubmitted: (_) => onSearch(),
                      cursorColor: Colors.white,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        height: 1.1,
                      ),
                      decoration: InputDecoration(
                        filled: false,
                        fillColor: Colors.transparent,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        hintText: hintText,
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 18),
              ],
            ),
          ),
        ),
        if (onScanWithCamera != null) ...[
          const SizedBox(width: 12),
          SizedBox(
            width: 58,
            height: 58,
            child: FilledButton(
              onPressed: loading ? null : onScanWithCamera,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.yellow,
                foregroundColor: AppTheme.blueDark,
                disabledBackgroundColor: const Color(0xFFE8D9AA),
                disabledForegroundColor: const Color(0xFF7C879C),
                elevation: 0,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: AppTheme.radiusMedium,
                  side: const BorderSide(
                    color: AppTheme.blueDark,
                    width: AppTheme.borderWidth,
                  ),
                ),
              ),
              child: const Icon(Icons.camera_alt_rounded, size: 26),
            ),
          ),
        ],
      ],
    );
  }
}

class _ScanCameraButton extends StatelessWidget {
  const _ScanCameraButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      height: 56,
      child: FilledButton(
        onPressed: enabled
            ? () {
                onPressed();
              }
            : null,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.yellow,
          foregroundColor: AppTheme.blue,
          disabledBackgroundColor: const Color(0xFFE8D9AA),
          disabledForegroundColor: const Color(0xFF7C879C),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: AppTheme.radiusMedium,
            side: const BorderSide(color: AppTheme.blue, width: 1.2),
          ),
          elevation: 0,
        ),
        child: const Icon(Icons.camera_alt_rounded, size: 24),
      ),
    );
  }
}
