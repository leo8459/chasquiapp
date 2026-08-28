import 'package:flutter/material.dart';

import 'package:scan_agbc/nucleo/tema/app_theme.dart';

class ScanConfirmKeyboardOverlay extends StatelessWidget {
  const ScanConfirmKeyboardOverlay({
    super.key,
    required this.ocrTokens,
    required this.confirming,
    required this.saveDialogVisible,
    required this.showSuggestions,
    required this.maxVisibleSuggestionTokens,
    required this.onConfirm,
    required this.onAppendToken,
    required this.onToggleSuggestions,
  });

  final List<String> ocrTokens;
  final bool confirming;
  final bool saveDialogVisible;
  final bool showSuggestions;
  final int maxVisibleSuggestionTokens;
  final Future<void> Function() onConfirm;
  final ValueChanged<String> onAppendToken;
  final VoidCallback onToggleSuggestions;

  @override
  Widget build(BuildContext context) {
    if (saveDialogVisible) {
      return const SizedBox.shrink();
    }

    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    final baseBottom = keyboardInset > 0 ? keyboardInset + 12 : safeBottom + 16;

    final canShowSuggestions = ocrTokens.isNotEmpty;
    final showSuggestionsRibbon = canShowSuggestions && showSuggestions;
    final visibleTokenCount = showSuggestionsRibbon
        ? (ocrTokens.length < maxVisibleSuggestionTokens
              ? ocrTokens.length
              : maxVisibleSuggestionTokens)
        : 0;

    const suggestionsHeight = 58.0;
    const suggestionsSpacing = 10.0;
    final suggestionsBottom = baseBottom;
    final actionsBottom = showSuggestionsRibbon
        ? suggestionsBottom + suggestionsHeight + suggestionsSpacing
        : baseBottom;

    return Stack(
      children: [
        if (showSuggestionsRibbon)
          Positioned(
            left: 0,
            right: 0,
            bottom: suggestionsBottom,
            child: RepaintBoundary(
              child: _KeyboardSuggestionsBar(
                tokens: ocrTokens,
                visibleTokenCount: visibleTokenCount,
                onAppendToken: onAppendToken,
              ),
            ),
          ),
        Positioned(
          right: 14,
          bottom: actionsBottom,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _OcrToggleButton(
                enabled: canShowSuggestions,
                active: showSuggestionsRibbon,
                onPressed: onToggleSuggestions,
              ),
              const SizedBox(width: 8),
              _ConfirmFab(enabled: !confirming, onPressed: onConfirm),
            ],
          ),
        ),
      ],
    );
  }
}

class _OcrToggleButton extends StatelessWidget {
  const _OcrToggleButton({
    required this.enabled,
    required this.active,
    required this.onPressed,
  });

  final bool enabled;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: enabled ? onPressed : null,
      style: FilledButton.styleFrom(
        backgroundColor: active ? AppTheme.blue : AppTheme.yellow,
        foregroundColor: active ? Colors.white : AppTheme.blue,
        disabledBackgroundColor: const Color(0xFFE7D6AA),
        disabledForegroundColor: const Color(0xFF8A8A8A),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      child: const Text('OCR', style: TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}

class _ConfirmFab extends StatelessWidget {
  const _ConfirmFab({required this.enabled, required this.onPressed});

  final bool enabled;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: 'confirm-mini',
      onPressed: enabled
          ? () {
              onPressed();
            }
          : null,
      backgroundColor: AppTheme.blue,
      foregroundColor: Colors.white,
      tooltip: 'Confirmar',
      child: const Icon(Icons.task_alt_rounded),
    );
  }
}

class _KeyboardSuggestionsBar extends StatelessWidget {
  const _KeyboardSuggestionsBar({
    required this.tokens,
    required this.visibleTokenCount,
    required this.onAppendToken,
  });

  final List<String> tokens;
  final int visibleTokenCount;
  final ValueChanged<String> onAppendToken;

  @override
  Widget build(BuildContext context) {
    if (visibleTokenCount == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: Colors.transparent,
        elevation: 10,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 58,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFFDECC0),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.blue, width: 1.2),
          ),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: visibleTokenCount,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final token = tokens[index];
              return InkWell(
                onTap: () => onAppendToken(token),
                borderRadius: BorderRadius.circular(999),
                child: Ink(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFCE3A6),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppTheme.blue),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.add_rounded,
                        size: 16,
                        color: AppTheme.blue,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        token,
                        style: const TextStyle(
                          color: AppTheme.blue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
