import 'package:flutter/material.dart';

import 'package:scan_agbc/nucleo/tema/app_theme.dart';
import 'package:flutter/services.dart';

import 'package:scan_agbc/funcionalidades/clasificacion/dominio/modelos/ventanilla_option.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/utilidades/app_strings.dart';

class ScanConfirmSectionCard extends StatelessWidget {
  const ScanConfirmSectionCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.yellowSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.blue),
      ),
      child: child,
    );
  }
}

class ScanConfirmCityDropdownField extends StatelessWidget {
  const ScanConfirmCityDropdownField({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SelectorFieldContainer(
      label: AppStrings.labelCiudad,
      icon: Icons.location_city_outlined,
      child: _SelectorButton(
        text: value,
        borderColor: _resolveFieldBorderColor(highlightError: false),
        fillColor: _resolveFieldFillColor(highlightError: false),
        onTap: () async {
          _dismissAnyFocus(context);
          final selected = await _showStringSelector(
            context,
            title: 'Selecciona ciudad',
            options: options,
          );
          onChanged(selected);
        },
      ),
    );
  }
}

class ScanConfirmBooleanDropdownField extends StatelessWidget {
  const ScanConfirmBooleanDropdownField({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
    this.highlightError = false,
  });

  final String label;
  final IconData icon;
  final bool value;
  final ValueChanged<bool?> onChanged;
  final bool highlightError;

  @override
  Widget build(BuildContext context) {
    return _SelectorFieldContainer(
      label: label,
      icon: icon,
      highlightError: highlightError,
      child: _SelectorButton(
        text: value ? 'SI' : 'NO',
        borderColor: _resolveFieldBorderColor(highlightError: highlightError),
        fillColor: _resolveFieldFillColor(highlightError: highlightError),
        onTap: () async {
          _dismissAnyFocus(context);
          final selected = await _showTopSelector<bool>(
            context,
            title: label,
            entries: const [
              _SelectorEntry<bool>(label: 'SI', value: true),
              _SelectorEntry<bool>(label: 'NO', value: false),
            ],
          );
          onChanged(selected);
        },
      ),
    );
  }
}

class ScanConfirmStringDropdownField extends StatelessWidget {
  const ScanConfirmStringDropdownField({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.options,
    required this.onChanged,
    this.highlightError = false,
  });

  final String label;
  final IconData icon;
  final String value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  final bool highlightError;

  @override
  Widget build(BuildContext context) {
    return _SelectorFieldContainer(
      label: label,
      icon: icon,
      highlightError: highlightError,
      child: _SelectorButton(
        text: value,
        borderColor: _resolveFieldBorderColor(highlightError: highlightError),
        fillColor: _resolveFieldFillColor(highlightError: highlightError),
        onTap: () async {
          _dismissAnyFocus(context);
          final selected = await _showStringSelector(
            context,
            title: 'Selecciona $label',
            options: options,
          );
          onChanged(selected);
        },
      ),
    );
  }
}

class ScanConfirmVentanillaDropdownField extends StatelessWidget {
  const ScanConfirmVentanillaDropdownField({
    super.key,
    required this.loading,
    required this.options,
    required this.value,
    required this.onChanged,
    this.highlightError = false,
  });

  final bool loading;
  final List<VentanillaOption> options;
  final int? value;
  final ValueChanged<int?> onChanged;
  final bool highlightError;

  @override
  Widget build(BuildContext context) {
    final selectedLabel = options
        .where((item) => item.id == value)
        .map((item) => item.label)
        .cast<String?>()
        .firstWhere((label) => label != null, orElse: () => null);

    return _SelectorFieldContainer(
      label: AppStrings.labelVentanilla,
      icon: Icons.meeting_room_outlined,
      highlightError: highlightError,
      child: loading
          ? const LinearProgressIndicator(
              minHeight: 6,
              color: AppTheme.blue,
              backgroundColor: AppTheme.yellowField,
            )
          : options.isEmpty
          ? const Text(
              'No hay ventanillas disponibles.',
              style: TextStyle(
                color: AppTheme.blue,
                fontWeight: FontWeight.w700,
              ),
            )
          : _SelectorButton(
              text: selectedLabel ?? AppStrings.hintSelectVentanilla,
              borderColor: _resolveFieldBorderColor(
                highlightError: highlightError,
              ),
              fillColor: _resolveFieldFillColor(highlightError: highlightError),
              onTap: () async {
                _dismissAnyFocus(context);
                final selected = await _showTopSelector<int>(
                  context,
                  title: 'Ventanilla',
                  entries: options.map((item) {
                    return _SelectorEntry<int>(
                      label: item.label,
                      value: item.id,
                    );
                  }).toList(),
                );
                onChanged(selected);
              },
            ),
    );
  }
}

class ScanConfirmInfoField extends StatelessWidget {
  const ScanConfirmInfoField({
    super.key,
    required this.label,
    required this.icon,
    required this.controller,
    required this.focusNode,
    this.forceUppercase = true,
    this.inputFormatters,
    this.keyboardType,
    this.textInputAction,
    this.onEditingComplete,
    this.highlightError = false,
  });

  final String label;
  final IconData icon;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool forceUppercase;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final VoidCallback? onEditingComplete;
  final bool highlightError;
  static const OutlineInputBorder _fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(10)),
    borderSide: BorderSide(color: AppTheme.blue),
  );
  static const OutlineInputBorder _focusedFieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(10)),
    borderSide: BorderSide(color: AppTheme.blue, width: 1.6),
  );

  @override
  Widget build(BuildContext context) {
    final borderColor = _resolveFieldBorderColor(
      highlightError: highlightError,
    );
    final surfaceColor = _resolveFieldSurfaceColor(
      highlightError: highlightError,
    );
    final fillColor = _resolveFieldFillColor(highlightError: highlightError);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.blue),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            focusNode: focusNode,
            maxLines: 1,
            keyboardType: keyboardType,
            textCapitalization: TextCapitalization.characters,
            inputFormatters:
                inputFormatters ??
                (forceUppercase
                    ? const [ScanConfirmUpperCaseTextFormatter()]
                    : null),
            textInputAction: textInputAction,
            onEditingComplete: onEditingComplete,
            scrollPadding: const EdgeInsets.only(bottom: 130),
            style: const TextStyle(
              color: AppTheme.blue,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: fillColor,
              border: _fieldBorder.copyWith(
                borderSide: BorderSide(color: borderColor),
              ),
              enabledBorder: _fieldBorder.copyWith(
                borderSide: BorderSide(color: borderColor),
              ),
              focusedBorder: _focusedFieldBorder.copyWith(
                borderSide: BorderSide(color: borderColor, width: 1.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectorFieldContainer extends StatelessWidget {
  const _SelectorFieldContainer({
    required this.label,
    required this.icon,
    required this.child,
    this.highlightError = false,
  });

  final String label;
  final IconData icon;
  final Widget child;
  final bool highlightError;

  @override
  Widget build(BuildContext context) {
    final borderColor = _resolveFieldBorderColor(
      highlightError: highlightError,
    );
    final surfaceColor = _resolveFieldSurfaceColor(
      highlightError: highlightError,
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.blue),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _SelectorButton extends StatelessWidget {
  const _SelectorButton({
    required this.text,
    required this.onTap,
    this.borderColor,
    this.fillColor,
  });

  final String text;
  final VoidCallback onTap;
  final Color? borderColor;
  final Color? fillColor;
  static const OutlineInputBorder _selectorBorder = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(10)),
    borderSide: BorderSide(color: AppTheme.blue),
  );

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: InputDecorator(
            isFocused: false,
            isEmpty: false,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: fillColor ?? AppTheme.yellowField,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ),
              border: _selectorBorder.copyWith(
                borderSide: BorderSide(color: borderColor ?? AppTheme.blue),
              ),
              enabledBorder: _selectorBorder.copyWith(
                borderSide: BorderSide(color: borderColor ?? AppTheme.blue),
              ),
              focusedBorder: _selectorBorder.copyWith(
                borderSide: BorderSide(color: borderColor ?? AppTheme.blue),
              ),
              suffixIcon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppTheme.blue,
              ),
            ),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.blue,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<String?> _showStringSelector(
  BuildContext context, {
  required String title,
  required List<String> options,
}) {
  final entries = options
      .map((item) => _SelectorEntry<String>(label: item, value: item))
      .toList();
  return _showTopSelector<String>(context, title: title, entries: entries);
}

class _SelectorEntry<T> {
  const _SelectorEntry({required this.label, required this.value});

  final String label;
  final T value;
}

void _dismissAnyFocus(BuildContext context) {
  FocusManager.instance.primaryFocus?.unfocus();
  FocusScope.of(context).unfocus(disposition: UnfocusDisposition.scope);
}

Future<T?> _showTopSelector<T>(
  BuildContext context, {
  required String title,
  required List<_SelectorEntry<T>> entries,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'selector',
    barrierColor: const Color(0x551B305F),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, animation, secondaryAnimation) =>
        const SizedBox.shrink(),
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SafeArea(
        child: Center(
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(curved),
            child: FadeTransition(
              opacity: curved,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  constraints: const BoxConstraints(
                    maxHeight: 420,
                    maxWidth: 520,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.yellowField,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.blue),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        title: Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppTheme.blue,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: AppTheme.blue,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const Divider(height: 1, color: AppTheme.blue),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            return ListTile(
                              title: Text(
                                entry.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.blue,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              onTap: () =>
                                  Navigator.of(context).pop(entry.value),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class ScanConfirmUpperCaseTextFormatter extends TextInputFormatter {
  const ScanConfirmUpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

Color _resolveFieldBorderColor({required bool highlightError}) {
  if (highlightError) return AppTheme.errorRed;
  return AppTheme.blue;
}

Color _resolveFieldSurfaceColor({required bool highlightError}) {
  if (highlightError) return AppTheme.errorSoft;
  return AppTheme.yellowSurface;
}

Color _resolveFieldFillColor({required bool highlightError}) {
  if (highlightError) return AppTheme.errorSoft;
  return AppTheme.yellowField;
}
