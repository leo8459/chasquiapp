import '../modelos/package_tracking_result.dart';

class PackageCodeValidationResult {
  const PackageCodeValidationResult({
    required this.normalizedCode,
    required this.errorMessage,
  });

  const PackageCodeValidationResult.valid(String normalizedCode)
    : this(normalizedCode: normalizedCode, errorMessage: null);

  final String normalizedCode;
  final String? errorMessage;

  bool get isValid => errorMessage == null;
}

class PackageSearchPlan {
  const PackageSearchPlan({
    required this.normalizedCode,
    required this.targets,
    required this.searchAll,
  });

  final String normalizedCode;
  final List<PackageCategory> targets;
  final bool searchAll;
}

class PackageCodeClassifier {
  static const String _allowedInitialChars = 'CURLEOS0DPAM1I';
  static final RegExp _searchCodePattern = RegExp(
    r'^[CURLEOS0DPAM1I][A-Z0-9]*$',
  );
  static final RegExp _digitPattern = RegExp(r'\d');
  static final RegExp _ocrNoisePattern = RegExp(r'[^A-Z0-9]+');
  static final RegExp _emsGeneric = RegExp(r'^E[A-Z]');
  static final RegExp _ag = RegExp(r'^AG');
  static final RegExp _certiRr = RegExp(r'^RR');
  static final RegExp _certiRp = RegExp(r'^RP');
  static final RegExp _contrato = RegExp(r'^C0');
  static final RegExp _ordiCp = RegExp(r'^CP');
  static final RegExp _ordiRd = RegExp(r'^RD');
  static final RegExp _ordiOr = RegExp(r'^OR');
  static final RegExp _ordiUx = RegExp(r'^U[A-Z]');

  static const List<PackageCategory> _allTargets = [
    PackageCategory.ems,
    PackageCategory.certi,
    PackageCategory.contrato,
    PackageCategory.ordi,
  ];

  static String normalize(String rawCode) {
    return rawCode.toUpperCase().replaceAll(_ocrNoisePattern, '').trim();
  }

  static Iterable<String> extractSearchCandidates(String rawText) sync* {
    final normalized = normalize(rawText);
    if (normalized.isEmpty) return;

    final seen = <String>{};
    for (final candidate in _buildCandidateWindows(normalized)) {
      final validation = validateForSearch(candidate);
      if (validation.isValid && seen.add(validation.normalizedCode)) {
        yield validation.normalizedCode;
      }
    }
  }

  static Iterable<String> extractSearchCandidatesFromOcr(String rawText) sync* {
    final normalized = rawText.toUpperCase().replaceAll(_ocrNoisePattern, '');
    if (normalized.isEmpty) return;

    final seen = <String>{};
    for (final candidate in _buildCandidateWindows(normalized)) {
      for (final variant in _buildOcrCandidateVariants(candidate)) {
        final validation = validateForSearch(variant);
        if (validation.isValid && seen.add(validation.normalizedCode)) {
          yield validation.normalizedCode;
        }
      }
    }
  }

  static PackageCodeValidationResult validateForSearch(String rawCode) {
    final normalizedCode = normalize(rawCode);
    if (normalizedCode.isEmpty) {
      return const PackageCodeValidationResult(
        normalizedCode: '',
        errorMessage: 'Ingresa un código.',
      );
    }

    if (!_allowedInitialChars.contains(normalizedCode.substring(0, 1))) {
      return PackageCodeValidationResult(
        normalizedCode: normalizedCode,
        errorMessage:
            'El código debe empezar con una letra válida o con el número 0.',
      );
    }

    final digitsCount = _digitPattern.allMatches(normalizedCode).length;
    if (digitsCount < 8) {
      return PackageCodeValidationResult(
        normalizedCode: normalizedCode,
        errorMessage: 'El código debe tener al menos 8 números.',
      );
    }

    if (!_searchCodePattern.hasMatch(normalizedCode)) {
      return PackageCodeValidationResult(
        normalizedCode: normalizedCode,
        errorMessage: 'Revisa el formato del código e intenta nuevamente.',
      );
    }

    return PackageCodeValidationResult.valid(normalizedCode);
  }

  static PackageSearchPlan build(String rawCode) {
    final validation = validateForSearch(rawCode);
    final normalizedCode = validation.normalizedCode;
    if (!validation.isValid || normalizedCode.isEmpty) {
      return const PackageSearchPlan(
        normalizedCode: '',
        targets: <PackageCategory>[],
        searchAll: false,
      );
    }

    if (_emsGeneric.hasMatch(normalizedCode) || _ag.hasMatch(normalizedCode)) {
      return PackageSearchPlan(
        normalizedCode: normalizedCode,
        targets: const <PackageCategory>[PackageCategory.ems],
        searchAll: false,
      );
    }

    if (_certiRr.hasMatch(normalizedCode) ||
        _certiRp.hasMatch(normalizedCode)) {
      return PackageSearchPlan(
        normalizedCode: normalizedCode,
        targets: const <PackageCategory>[PackageCategory.certi],
        searchAll: false,
      );
    }

    if (_contrato.hasMatch(normalizedCode)) {
      return PackageSearchPlan(
        normalizedCode: normalizedCode,
        targets: const <PackageCategory>[PackageCategory.contrato],
        searchAll: false,
      );
    }

    if (_ordiCp.hasMatch(normalizedCode) ||
        _ordiRd.hasMatch(normalizedCode) ||
        _ordiOr.hasMatch(normalizedCode) ||
        _ordiUx.hasMatch(normalizedCode)) {
      return PackageSearchPlan(
        normalizedCode: normalizedCode,
        targets: const <PackageCategory>[PackageCategory.ordi],
        searchAll: false,
      );
    }

    return PackageSearchPlan(
      normalizedCode: normalizedCode,
      targets: _allTargets,
      searchAll: true,
    );
  }

  static Iterable<String> _buildCandidateWindows(String normalized) sync* {
    yield normalized;
    if (normalized.length <= 13) return;

    for (var index = 0; index <= normalized.length - 13; index++) {
      yield normalized.substring(index, index + 13);
    }
  }

  static Iterable<String> _buildOcrCandidateVariants(String candidate) sync* {
    yield candidate;
    if (candidate.length != 13) return;

    final repaired = _repairTrackingCode(candidate);
    if (repaired != candidate) {
      yield repaired;
    }

    final repairedSecondChar = _repairTrackingCode(
      candidate,
      forceLetterAtSecondPosition: true,
    );
    if (repairedSecondChar != candidate && repairedSecondChar != repaired) {
      yield repairedSecondChar;
    }
  }

  static String _repairTrackingCode(
    String candidate, {
    bool forceLetterAtSecondPosition = false,
  }) {
    if (candidate.length != 13) return candidate;

    final chars = candidate.split('');
    chars[0] = _repairInitialChar(chars[0]);
    if (forceLetterAtSecondPosition) {
      chars[1] = _repairLetterLikeChar(chars[1]);
    }
    for (var index = 2; index <= 10; index++) {
      chars[index] = _repairDigitLikeChar(chars[index]);
    }
    chars[11] = _repairLetterLikeChar(chars[11]);
    chars[12] = _repairLetterLikeChar(chars[12]);
    return chars.join();
  }

  static String _repairInitialChar(String value) {
    switch (value) {
      case '0':
      case 'Q':
      case 'D':
        return 'O';
      case 'G':
        return 'C';
      default:
        return value;
    }
  }

  static String _repairDigitLikeChar(String value) {
    switch (value) {
      case 'O':
      case 'Q':
      case 'D':
        return '0';
      case 'I':
      case 'L':
        return '1';
      case 'Z':
        return '2';
      case 'A':
        return '4';
      case 'S':
        return '5';
      case 'G':
        return '6';
      case 'T':
        return '7';
      case 'B':
        return '8';
      default:
        return value;
    }
  }

  static String _repairLetterLikeChar(String value) {
    switch (value) {
      case '0':
        return 'O';
      case '1':
        return 'I';
      case '2':
        return 'Z';
      case '4':
        return 'A';
      case '5':
        return 'S';
      case '6':
        return 'G';
      case '7':
        return 'T';
      case '8':
        return 'B';
      default:
        return value;
    }
  }
}
