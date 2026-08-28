import 'app_strings.dart';

class ScanConfirmFieldKeys {
  const ScanConfirmFieldKeys._();

  static const String ventanilla = 'ventanilla';
  static const String barcode = 'barcode';
  static const String nombre = 'nombre';
  static const String telefono = 'telefono';
  static const String peso = 'peso';
}

class ScanConfirmValidationResult {
  const ScanConfirmValidationResult({
    required this.errorMessage,
    required this.fieldKey,
    this.peso,
  });

  final String? errorMessage;
  final String? fieldKey;
  final double? peso;

  bool get isValid => errorMessage == null;
}

class ScanConfirmValidator {
  const ScanConfirmValidator._();

  static const List<String> _validBarcodePrefixes = ['R', 'U', 'L'];

  static ScanConfirmValidationResult validate({
    required int? ventanillaId,
    required String barcode,
    required String nombre,
    required String telefono,
    required String pesoRaw,
  }) {
    if (ventanillaId == null) {
      return const ScanConfirmValidationResult(
        errorMessage: AppStrings.errorSelectVentanilla,
        fieldKey: ScanConfirmFieldKeys.ventanilla,
      );
    }

    if (barcode.trim().isEmpty) {
      return const ScanConfirmValidationResult(
        errorMessage: AppStrings.errorBarcodeRequired,
        fieldKey: ScanConfirmFieldKeys.barcode,
      );
    }

    final prefix = barcode.trim().substring(0, 1).toUpperCase();
    if (!_validBarcodePrefixes.contains(prefix)) {
      return const ScanConfirmValidationResult(
        errorMessage: AppStrings.errorBarcodeInvalid,
        fieldKey: ScanConfirmFieldKeys.barcode,
      );
    }

    if (nombre.trim().isEmpty) {
      return const ScanConfirmValidationResult(
        errorMessage: AppStrings.errorNombreRequired,
        fieldKey: ScanConfirmFieldKeys.nombre,
      );
    }

    final normalizedTelefono = telefono.replaceAll(RegExp(r'\D'), '');
    if (normalizedTelefono.isNotEmpty &&
        (normalizedTelefono.length < 7 || normalizedTelefono.length > 15)) {
      return const ScanConfirmValidationResult(
        errorMessage: AppStrings.errorTelefonoInvalid,
        fieldKey: ScanConfirmFieldKeys.telefono,
      );
    }

    final trimmedPeso = pesoRaw.trim();
    if (trimmedPeso.isEmpty) {
      return const ScanConfirmValidationResult(
        errorMessage: AppStrings.errorPesoRequired,
        fieldKey: ScanConfirmFieldKeys.peso,
      );
    }

    final parsedPeso = double.tryParse(trimmedPeso.replaceAll(',', '.'));
    if (parsedPeso == null) {
      return const ScanConfirmValidationResult(
        errorMessage: AppStrings.errorPesoNumeric,
        fieldKey: ScanConfirmFieldKeys.peso,
      );
    }

    return ScanConfirmValidationResult(
      errorMessage: null,
      fieldKey: null,
      peso: parsedPeso,
    );
  }
}
