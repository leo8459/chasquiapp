import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:scan_agbc/funcionalidades/clasificacion/dominio/modelos/ventanilla_option.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/utilidades/app_strings.dart';
import 'scan_confirm_shared_widgets.dart';

class ScanConfirmFieldsSection extends StatelessWidget {
  const ScanConfirmFieldsSection({
    super.key,
    required this.barcodeController,
    required this.nombreController,
    required this.telefonoController,
    required this.pesoController,
    required this.barcodeFocusNode,
    required this.nombreFocusNode,
    required this.telefonoFocusNode,
    required this.pesoFocusNode,
    required this.selectedCiudad,
    required this.tipoDocumentoListenable,
    required this.isAduana,
    required this.loadingVentanillas,
    required this.ventanillas,
    required this.selectedVentanillaId,
    required this.departamentos,
    required this.tipoDocumentoOpciones,
    required this.onCiudadChanged,
    required this.onTipoDocumentoChanged,
    required this.onAduanaChanged,
    required this.onVentanillaChanged,
    this.showValidationErrors = false,
    this.barcodeFieldKey,
    this.nombreFieldKey,
    this.telefonoFieldKey,
    this.pesoFieldKey,
    this.ventanillaFieldKey,
  });

  final TextEditingController barcodeController;
  final TextEditingController nombreController;
  final TextEditingController telefonoController;
  final TextEditingController pesoController;
  final FocusNode barcodeFocusNode;
  final FocusNode nombreFocusNode;
  final FocusNode telefonoFocusNode;
  final FocusNode pesoFocusNode;
  final String selectedCiudad;
  final ValueListenable<String> tipoDocumentoListenable;
  final bool isAduana;
  final bool loadingVentanillas;
  final List<VentanillaOption> ventanillas;
  final int? selectedVentanillaId;
  final List<String> departamentos;
  final List<String> tipoDocumentoOpciones;
  final ValueChanged<String> onCiudadChanged;
  final ValueChanged<String> onTipoDocumentoChanged;
  final ValueChanged<bool> onAduanaChanged;
  final ValueChanged<int> onVentanillaChanged;
  final bool showValidationErrors;
  final Key? barcodeFieldKey;
  final Key? nombreFieldKey;
  final Key? telefonoFieldKey;
  final Key? pesoFieldKey;
  final Key? ventanillaFieldKey;

  @override
  Widget build(BuildContext context) {
    const pesoFormatter = _DecimalInputFormatter(
      decimalRange: 3,
      maxIntegerDigits: 3,
    );

    return ScanConfirmSectionCard(
      child: Column(
        children: [
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: barcodeController,
            builder: (context, value, _) {
              final hasValue = value.text.trim().isNotEmpty;
              return ScanConfirmInfoField(
                key: barcodeFieldKey,
                label: AppStrings.labelBarcode,
                icon: Icons.qr_code_2_rounded,
                controller: barcodeController,
                focusNode: barcodeFocusNode,
                highlightError: showValidationErrors && !hasValue,
                textInputAction: TextInputAction.next,
                onEditingComplete: () {
                  nombreFocusNode.requestFocus();
                },
              );
            },
          ),
          const SizedBox(height: 10),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: nombreController,
            builder: (context, value, _) {
              final hasValue = value.text.trim().isNotEmpty;
              return ScanConfirmInfoField(
                key: nombreFieldKey,
                label: AppStrings.labelNombre,
                icon: Icons.badge_outlined,
                controller: nombreController,
                focusNode: nombreFocusNode,
                highlightError: showValidationErrors && !hasValue,
                textInputAction: TextInputAction.next,
                onEditingComplete: () {
                  telefonoFocusNode.requestFocus();
                },
              );
            },
          ),
          const SizedBox(height: 10),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: telefonoController,
            builder: (context, value, _) {
              final normalized = value.text.trim().replaceAll(
                RegExp(r'\D'),
                '',
              );
              final hasValue = normalized.isNotEmpty;
              final validLength =
                  normalized.length >= 7 && normalized.length <= 15;
              return ScanConfirmInfoField(
                key: telefonoFieldKey,
                label: AppStrings.labelTelefono,
                icon: Icons.phone_outlined,
                controller: telefonoController,
                focusNode: telefonoFocusNode,
                keyboardType: TextInputType.phone,
                forceUppercase: false,
                highlightError:
                    showValidationErrors && hasValue && !validLength,
                textInputAction: TextInputAction.next,
                onEditingComplete: () {
                  pesoFocusNode.requestFocus();
                },
              );
            },
          ),
          const SizedBox(height: 10),
          ScanConfirmCityDropdownField(
            value: selectedCiudad,
            options: departamentos,
            onChanged: (value) {
              if (value == null) return;
              onCiudadChanged(value);
            },
          ),
          const SizedBox(height: 10),
          ValueListenableBuilder<String>(
            valueListenable: tipoDocumentoListenable,
            builder: (context, value, _) {
              return ScanConfirmStringDropdownField(
                label: AppStrings.labelTipo,
                icon: Icons.category_outlined,
                value: value,
                options: tipoDocumentoOpciones,
                onChanged: (value) {
                  if (value == null) return;
                  onTipoDocumentoChanged(value);
                },
              );
            },
          ),
          const SizedBox(height: 10),
          ScanConfirmBooleanDropdownField(
            label: AppStrings.labelAduana,
            icon: Icons.gavel_outlined,
            value: isAduana,
            onChanged: (value) {
              if (value == null) return;
              onAduanaChanged(value);
            },
          ),
          const SizedBox(height: 10),
          ScanConfirmVentanillaDropdownField(
            key: ventanillaFieldKey,
            loading: loadingVentanillas,
            options: ventanillas,
            value: selectedVentanillaId,
            highlightError:
                showValidationErrors && selectedVentanillaId == null,
            onChanged: (value) {
              if (value == null) return;
              onVentanillaChanged(value);
            },
          ),
          const SizedBox(height: 10),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: pesoController,
            builder: (context, value, _) {
              final hasValue = value.text.trim().isNotEmpty;
              return ScanConfirmInfoField(
                key: pesoFieldKey,
                label: AppStrings.labelPesoManual,
                icon: Icons.monitor_weight_outlined,
                controller: pesoController,
                focusNode: pesoFocusNode,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                forceUppercase: false,
                inputFormatters: const [pesoFormatter],
                highlightError: showValidationErrors && !hasValue,
                textInputAction: TextInputAction.done,
                onEditingComplete: () => FocusScope.of(context).unfocus(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DecimalInputFormatter extends TextInputFormatter {
  const _DecimalInputFormatter({
    required this.decimalRange,
    required this.maxIntegerDigits,
  });

  final int decimalRange;
  final int maxIntegerDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text;
    if (raw.isEmpty) return newValue;

    final hasComma = raw.contains(',') && !raw.contains('.');
    final separator = hasComma ? ',' : '.';
    var normalized = raw.replaceAll(',', '.');
    normalized = normalized.replaceAll(RegExp(r'[^0-9.]'), '');

    final dotIndex = normalized.indexOf('.');
    if (dotIndex != -1) {
      final before = normalized.substring(0, dotIndex);
      var after = normalized.substring(dotIndex + 1).replaceAll('.', '');
      if (before.length > maxIntegerDigits) {
        return oldValue;
      }
      if (after.length > decimalRange) {
        after = after.substring(0, decimalRange);
      }
      normalized = '$before.$after';
    } else if (normalized.length > maxIntegerDigits) {
      return oldValue;
    }

    var display = normalized;
    if (separator == ',') {
      display = normalized.replaceFirst('.', ',');
    }

    final selectionIndex = display.length;
    return TextEditingValue(
      text: display,
      selection: TextSelection.collapsed(offset: selectionIndex),
    );
  }
}
