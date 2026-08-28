import 'dart:async';

import 'package:flutter/material.dart';

import 'package:scan_agbc/nucleo/tema/app_theme.dart';

enum AppFeedbackTone { info, success, error }

enum AppFeedbackPlacement { bottom, top }

final GlobalKey<ScaffoldMessengerState> appScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
OverlayEntry? _activeTopFeedbackEntry;
Timer? _activeTopFeedbackTimer;

void showAppFeedbackBanner(
  BuildContext context,
  String message, {
  AppFeedbackTone tone = AppFeedbackTone.info,
  Duration duration = const Duration(milliseconds: 2400),
  IconData? icon,
  AppFeedbackPlacement placement = AppFeedbackPlacement.top,
  double? topOffset,
}) {
  final messenger =
      appScaffoldMessengerKey.currentState ??
      ScaffoldMessenger.maybeOf(context);
  if (messenger == null && placement == AppFeedbackPlacement.bottom) return;

  final (backgroundColor, foregroundColor, defaultIcon) = switch (tone) {
    AppFeedbackTone.error => (
      AppTheme.errorRed,
      Colors.white,
      Icons.error_outline_rounded,
    ),
    AppFeedbackTone.success => (
      AppTheme.successGreen,
      Colors.white,
      Icons.task_alt_rounded,
    ),
    AppFeedbackTone.info => (
      AppTheme.blue,
      Colors.white,
      Icons.info_outline_rounded,
    ),
  };

  if (placement == AppFeedbackPlacement.top) {
    final rootOverlay = appScaffoldMessengerKey.currentContext == null
        ? null
        : Overlay.maybeOf(
            appScaffoldMessengerKey.currentContext!,
            rootOverlay: true,
          );
    final overlay = rootOverlay ?? Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _removeTopFeedback();

    final entry = OverlayEntry(
      builder: (context) {
        final resolvedTopInset =
            topOffset ??
            (MediaQuery.of(context).viewPadding.top + kToolbarHeight + 12);
        return Positioned(
          top: resolvedTopInset,
          left: 16,
          right: 16,
          child: IgnorePointer(
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 14,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(icon ?? defaultIcon, color: foregroundColor, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        message,
                        style: TextStyle(
                          color: foregroundColor,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);
    _activeTopFeedbackEntry = entry;
    _activeTopFeedbackTimer = Timer(duration, _removeTopFeedback);
    return;
  }

  final bottomMessenger = messenger;
  if (bottomMessenger == null) return;

  bottomMessenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: duration,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 22),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        backgroundColor: backgroundColor,
        dismissDirection: DismissDirection.horizontal,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: foregroundColor.withValues(alpha: 0.18)),
        ),
        content: Row(
          children: [
            Icon(icon ?? defaultIcon, color: foregroundColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: foregroundColor,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
}

void _removeTopFeedback() {
  _activeTopFeedbackTimer?.cancel();
  _activeTopFeedbackTimer = null;
  _activeTopFeedbackEntry?.remove();
  _activeTopFeedbackEntry = null;
}
