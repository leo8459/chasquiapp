import 'package:flutter/material.dart';

import 'package:scan_agbc/nucleo/tema/app_theme.dart';

class AppPanelCard extends StatelessWidget {
  const AppPanelCard({
    super.key,
    required this.child,
    this.width,
    this.padding = AppTheme.panelPadding,
    this.margin,
    this.backgroundColor = AppTheme.yellowSoft,
    this.borderRadius = AppTheme.radiusXLarge,
    this.borderColor = AppTheme.softBorder,
    this.boxShadow,
  });

  final Widget child;
  final double? width;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color backgroundColor;
  final BorderRadius borderRadius;
  final Color borderColor;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      margin: margin,
      padding: padding,
      decoration: AppTheme.buildPanelDecoration(
        backgroundColor: backgroundColor,
        borderRadius: borderRadius,
        borderColor: borderColor,
        boxShadow: boxShadow,
      ),
      child: child,
    );
  }
}

class AppSoftCard extends StatelessWidget {
  const AppSoftCard({
    super.key,
    required this.child,
    this.width,
    this.padding = AppTheme.sectionPadding,
    this.margin,
    this.backgroundColor = AppTheme.yellowSurface,
    this.borderRadius = AppTheme.radiusMedium,
    this.borderColor = AppTheme.lightBorder,
    this.boxShadow = const <BoxShadow>[],
  });

  final Widget child;
  final double? width;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color backgroundColor;
  final BorderRadius borderRadius;
  final Color borderColor;
  final List<BoxShadow> boxShadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      margin: margin,
      padding: padding,
      decoration: AppTheme.buildSoftCardDecoration(
        backgroundColor: backgroundColor,
        borderRadius: borderRadius,
        borderColor: borderColor,
        boxShadow: boxShadow,
      ),
      child: child,
    );
  }
}

class AppActionTray extends StatelessWidget {
  const AppActionTray({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(10, 10, 10, 10),
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return AppSoftCard(
      margin: margin,
      padding: padding,
      backgroundColor: const Color(0xD9FFF1CC),
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      borderColor: AppTheme.softBorder,
      boxShadow: const [
        BoxShadow(
          color: Color(0x2A1B305F),
          blurRadius: 12,
          offset: Offset(0, 5),
        ),
      ],
      child: child,
    );
  }
}

class AppSectionIntroCard extends StatelessWidget {
  const AppSectionIntroCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.eyebrow = 'Sección actual',
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String eyebrow;

  @override
  Widget build(BuildContext context) {
    return AppSoftCard(
      padding: const EdgeInsets.all(18),
      backgroundColor: const Color(0xF7FFF8EE),
      borderRadius: AppTheme.radiusLarge,
      borderColor: AppTheme.lightBorder,
      boxShadow: const [
        BoxShadow(
          color: Color(0x141B305F),
          blurRadius: 18,
          offset: Offset(0, 8),
        ),
      ],
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.actionYellowStrong,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.strongBorder, width: 1.4),
              boxShadow: const [
                BoxShadow(
                  color: AppTheme.softShadow,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: AppTheme.blueDark, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow.toUpperCase(),
                  style: const TextStyle(
                    color: AppTheme.blueMid,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.blueDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    height: 1.08,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppTheme.blueDark,
                    fontWeight: FontWeight.w600,
                    height: 1.32,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AppStatusMessageCard extends StatelessWidget {
  const AppStatusMessageCard({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.iconColor = AppTheme.blue,
    this.backgroundColor = AppTheme.yellowSoft,
    this.contentColor = AppTheme.blueDark,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final Color contentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x661B305F)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 30, color: iconColor),
          const SizedBox(height: 10),
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
            style: TextStyle(
              color: contentColor,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
