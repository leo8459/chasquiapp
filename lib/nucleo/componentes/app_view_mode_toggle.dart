import 'package:flutter/material.dart';

import 'package:scan_agbc/nucleo/tema/app_theme.dart';

class AppViewModeToggle extends StatelessWidget {
  const AppViewModeToggle({
    super.key,
    required this.gridEnabled,
    required this.onGridEnabledChanged,
    this.height = 40,
  });

  final bool gridEnabled;
  final ValueChanged<bool> onGridEnabledChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final padding = height * 0.08;
    final buttonHeight = height - (padding * 2);
    final buttonWidth = buttonHeight * 1.1;
    final iconSize = buttonHeight * 0.52;

    return Container(
      padding: EdgeInsets.all(padding),
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.yellowSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ViewModeButton(
            icon: Icons.view_agenda_rounded,
            selected: !gridEnabled,
            onTap: () => onGridEnabledChanged(false),
            width: buttonWidth,
            height: buttonHeight,
            iconSize: iconSize,
          ),
          _ViewModeButton(
            icon: Icons.grid_view_rounded,
            selected: gridEnabled,
            onTap: () => onGridEnabledChanged(true),
            width: buttonWidth,
            height: buttonHeight,
            iconSize: iconSize,
          ),
        ],
      ),
    );
  }
}

class _ViewModeButton extends StatelessWidget {
  const _ViewModeButton({
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.width,
    required this.height,
    required this.iconSize,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final double width;
  final double height;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: selected ? 'Vista actual' : 'Cambiar vista',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: selected ? null : onTap,
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: width,
            height: height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppTheme.blue : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(
              icon,
              size: iconSize,
              color: selected ? Colors.white : AppTheme.blue,
            ),
          ),
        ),
      ),
    );
  }
}
