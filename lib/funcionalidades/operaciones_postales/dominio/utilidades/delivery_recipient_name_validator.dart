class DeliveryRecipientNameValidationResult {
  const DeliveryRecipientNameValidationResult({
    required this.normalizedValue,
    this.errorMessage,
  });

  final String normalizedValue;
  final String? errorMessage;

  bool get isValid => errorMessage == null;
}

class DeliveryRecipientNameValidator {
  const DeliveryRecipientNameValidator._();

  static final RegExp _allowedCharactersPattern = RegExp(
    r'^[A-Za-zÁÉÍÓÚÑáéíóúñ\s-]+$',
  );
  static final RegExp _displayPattern = RegExp(
    r'^([A-ZÁÉÍÓÚÑ][a-záéíóúñ]+(?:[-\s][A-ZÁÉÍÓÚÑ][a-záéíóúñ]+)*)$',
  );
  static final RegExp _splitPattern = RegExp(r'[\s-]+');
  static final RegExp _vowelPattern = RegExp(r'[AEIOUÁÉÍÓÚaeiouáéíóú]');

  static String normalize(String rawValue) {
    final collapsed = rawValue
        .replaceAll(RegExp(r'\s*-\s*'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (collapsed.isEmpty) {
      return '';
    }

    return collapsed
        .split(' ')
        .where((segment) => segment.trim().isNotEmpty)
        .map(_normalizeWord)
        .join(' ');
  }

  static DeliveryRecipientNameValidationResult validate(String rawValue) {
    final normalizedValue = normalize(rawValue);
    if (normalizedValue.isEmpty) {
      return const DeliveryRecipientNameValidationResult(
        normalizedValue: '',
        errorMessage:
            'Escribe el nombre y apellido de quien recibe el paquete.',
      );
    }

    if (!_allowedCharactersPattern.hasMatch(normalizedValue)) {
      return DeliveryRecipientNameValidationResult(
        normalizedValue: normalizedValue,
        errorMessage:
            'Usa solo letras, espacios o guion en el nombre de quien recibe.',
      );
    }

    final parts = normalizedValue
        .split(_splitPattern)
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.any((part) => part.runes.length < 2)) {
      return DeliveryRecipientNameValidationResult(
        normalizedValue: normalizedValue,
        errorMessage:
            'Cada nombre o apellido debe tener al menos 2 letras completas.',
      );
    }

    if (parts.any((part) => !_vowelPattern.hasMatch(part))) {
      return DeliveryRecipientNameValidationResult(
        normalizedValue: normalizedValue,
        errorMessage:
            'Revisa el nombre ingresado. No uses abreviaturas ni bloques de consonantes.',
      );
    }

    if (!_displayPattern.hasMatch(normalizedValue)) {
      return DeliveryRecipientNameValidationResult(
        normalizedValue: normalizedValue,
        errorMessage:
            'Escribe un nombre válido, por ejemplo: Juan Perez o Maria-Laura.',
      );
    }

    return DeliveryRecipientNameValidationResult(
      normalizedValue: normalizedValue,
    );
  }

  static String _normalizeWord(String word) {
    return word
        .split('-')
        .where((segment) => segment.trim().isNotEmpty)
        .map(_toTitleCase)
        .join('-');
  }

  static String _toTitleCase(String value) {
    final lower = value.toLowerCase();
    if (lower.isEmpty) {
      return '';
    }
    return '${lower[0].toUpperCase()}${lower.substring(1)}';
  }
}
