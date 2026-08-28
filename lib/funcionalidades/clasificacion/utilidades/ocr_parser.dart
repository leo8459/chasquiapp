import 'package:scan_agbc/funcionalidades/clasificacion/dominio/modelos/scanned_ficha_data.dart';

ScannedFichaData parseScannedFichaData(Map<String, String> payload) {
  final barcodeText = payload['barcodeText'] ?? '';
  final ocrText = payload['ocrText'] ?? '';

  if (ocrText.trim().isEmpty) {
    return ScannedFichaData(
      barcode: _firstLine(barcodeText),
      nombre: '',
      direccion: '',
      telefono: '',
      ocrRaw: '',
      ocrTokens: const [],
    );
  }

  final normalizedOcrText = ocrText
      .replaceAll('\u00A0', ' ')
      .replaceAll('\u2007', ' ')
      .replaceAll('\u202F', ' ')
      .replaceAll('\u200B', '')
      .replaceAll('\u200C', '')
      .replaceAll('\u200D', '')
      .replaceAll('\uFEFF', '')
      .replaceAll('\u2060', '')
      .replaceAll('\r', '\n')
      .replaceAll('\u2028', '\n')
      .replaceAll('\u2029', '\n')
      .replaceAll('\t', ' ')
      .replaceAll(RegExp(r'[•‣∙·◦▪■◆●]'), '')
      .replaceAll(RegExp(r'[–—]'), '-');

  final lines = normalizedOcrText
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((line) => line.isNotEmpty)
      .toList();

  final barcodeFromOcr = barcodeText.trim().isEmpty
      ? _extractBarcodeFromOcr(lines)
      : null;

  final barcodeValue = barcodeText.trim().isEmpty
      ? (barcodeFromOcr ?? '')
      : _firstLine(barcodeText);

  final nombre =
      _coerceNameCandidate(
        lines,
        _extractByLabel(
          lines,
          labels: const ['nombre', 'destinatario', 'cliente'],
        ),
      ) ??
      _extractNameAfterLabel(
        lines,
        labels: const ['ship to', 'envio', 'envío', 'destino'],
      ) ??
      _extractNameFromMixedLine(lines) ??
      extractLikelyName(lines) ??
      '';
  final nombreFinal = _sanitizeNameCandidate(nombre) ?? '';

  final direccion =
      _extractByLabel(
        lines,
        labels: const ['direccion', 'dirección', 'domicilio'],
      ) ??
      _extractLikelyAddress(lines) ??
      '';

  final telefono = extractPhone(lines) ?? '';

  return ScannedFichaData(
    barcode: barcodeValue,
    nombre: nombreFinal,
    direccion: direccion,
    telefono: telefono,
    ocrRaw: ocrText,
    ocrTokens: _parseOcrTokens(ocrText),
  );
}

String? _extractNameAfterLabel(
  List<String> lines, {
  required List<String> labels,
}) {
  if (lines.isEmpty) return null;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final lower = line.toLowerCase();
    var matched = false;
    for (final label in labels) {
      if (lower.contains(label)) {
        matched = true;
        break;
      }
    }
    if (!matched) continue;

    // Look ahead a few lines for the best name candidate.
    String? best;
    var bestScore = -999;
    for (var j = i + 1; j < lines.length && j <= i + 4; j++) {
      final candidate = lines[j].trim();
      if (candidate.isEmpty) continue;
      if (RegExp(r'\d').hasMatch(candidate)) continue;
      final candidateLower = candidate.toLowerCase();
      if (_normalizedContainsAny(candidateLower, _addressStopwords) ||
          _normalizedContainsAny(candidateLower, _nameContextStopwords) ||
          _normalizedContainsAny(candidateLower, _phoneLabels)) {
        continue;
      }
      final score = _scoreNameCandidate(
        line: candidate,
        lineIndex: j,
        totalLines: lines.length,
      );
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    if (best != null && bestScore >= 3) return best;
  }
  return null;
}

String? _extractNameFromMixedLine(List<String> lines) {
  if (lines.isEmpty) return null;
  final stopwords = <String>{
    ..._addressStopwords,
    'zona',
    'barrio',
    'av',
    'avenida',
    'calle',
    'direccion',
    'dirección',
  };

  for (final line in lines) {
    final lower = line.toLowerCase();
    for (final word in stopwords) {
      final idx = lower.indexOf(word);
      if (idx <= 1) continue;
      final candidate = line.substring(0, idx).trim();
      if (candidate.isEmpty) continue;
      if (RegExp(r'\d').hasMatch(candidate)) continue;
      final score = _scoreNameCandidate(
        line: candidate,
        lineIndex: 0,
        totalLines: lines.length,
      );
      if (score >= 3) return candidate;
    }
  }
  return null;
}

String? _coerceNameCandidate(List<String> lines, String? value) {
  if (value == null) return null;
  var cleaned = value.trim();
  if (cleaned.isEmpty) return null;
  cleaned = cleaned.replaceAll(RegExp(r'^[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ]+'), '');
  cleaned = cleaned.replaceAll(RegExp(r'[\s:]+$'), '').trim();
  if (cleaned.isEmpty) return null;

  if (RegExp(r'\d').hasMatch(cleaned)) return null;
  if (_normalizedContainsAny(cleaned.toLowerCase(), _nameContextStopwords)) {
    return null;
  }
  if (_normalizedContainsAny(cleaned.toLowerCase(), _addressStopwords)) {
    return null;
  }
  if (_normalizedContainsAny(cleaned.toLowerCase(), _phoneLabels)) {
    return null;
  }
  if (_isBoliviaDepartmentLine(cleaned) ||
      _containsBoliviaDepartmentMention(cleaned)) {
    return null;
  }

  final index = lines.indexWhere((line) => line.trim() == value.trim());
  final score = _scoreNameCandidate(
    line: cleaned,
    lineIndex: index >= 0 ? index : 0,
    totalLines: lines.length,
  );
  if (score < 3) return null;
  return cleaned;
}

List<String> _parseOcrTokens(String raw) {
  return raw
      .split(RegExp(r'\s+'))
      .map((token) => token.trim().replaceAll(RegExp(r'^[^\w+]+|[^\w]+$'), ''))
      .where((token) => token.isNotEmpty)
      .take(300)
      .toList(growable: false);
}

String _firstLine(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return '';
  return trimmed.split('\n').first.trim();
}

String? _extractBarcodeFromOcr(List<String> lines) {
  final regex = RegExp(r'[RUL][A-Z]?\d{7,12}[A-Z]{2}');
  for (final line in lines) {
    final compact = line.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final match = regex.firstMatch(compact);
    if (match != null) {
      return match.group(0);
    }
  }
  return null;
}

String? _extractByLabel(List<String> lines, {required List<String> labels}) {
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final lower = line.toLowerCase();
    for (final label in labels) {
      if (!lower.contains(label)) continue;
      if (_isLikelyLabelOnlyLine(line, label) && i + 1 < lines.length) {
        final nextLine = lines[i + 1].trim();
        if (nextLine.isEmpty) continue;
        final nextLower = nextLine.toLowerCase();
        final looksLikeAnotherLabel = labels.any(
          (candidate) => _isLikelyLabelOnlyLine(nextLine, candidate),
        );
        final isGenericLabel =
            _normalizedContainsAny(nextLower, _nameContextStopwords) ||
            _normalizedContainsAny(nextLower, _addressStopwords) ||
            _normalizedContainsAny(nextLower, _phoneLabels);
        if (looksLikeAnotherLabel || isGenericLabel) {
          continue;
        }
        return nextLine;
      }
      if (line.contains(':')) {
        final parts = line.split(':');
        if (parts.length > 1) {
          final value = parts.sublist(1).join(':').trim();
          if (value.isNotEmpty) return value;
        }
      }
      final replaced = line
          .replaceAll(RegExp(RegExp.escape(label), caseSensitive: false), '')
          .replaceAll('-', ' ')
          .trim();
      if (replaced.isNotEmpty) return replaced;
    }
  }
  return null;
}

bool _isLikelyLabelOnlyLine(String line, String label) {
  final normalizedLine = _normalizeText(
    line.replaceAll(RegExp(r'[:\-\s]+'), ''),
  );
  final normalizedLabel = _normalizeText(label);
  return normalizedLine == normalizedLabel;
}

String? extractLikelyName(List<String> lines) {
  var bestScore = -999;
  String? bestLine;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final score = _scoreNameCandidate(
      line: line,
      lineIndex: i,
      totalLines: lines.length,
    );
    if (score > bestScore) {
      bestScore = score;
      bestLine = line;
    }
  }

  if (bestLine == null || bestScore < 3) return null;
  if (_isBoliviaDepartmentLine(bestLine)) return null;
  return bestLine;
}

int _scoreNameCandidate({
  required String line,
  required int lineIndex,
  required int totalLines,
}) {
  final lower = line.toLowerCase();
  final normalized = _normalizeText(lower);

  if (lower.length < 6 || lower.length > 60) return -20;
  if (RegExp(r'\d').hasMatch(line)) return -20;
  if (_normalizedContainsAny(lower, _nameContextStopwords)) return -12;
  if (_isBoliviaDepartmentLine(line) ||
      _containsBoliviaDepartmentMention(line)) {
    return -40;
  }

  final words = _tokenizeWords(line);
  if (words.isEmpty) return -20;
  if (words.length == 1 || words.length > 5) return -8;

  var score = 0;
  if (words.length >= 2 && words.length <= 4) {
    score += 5;
  } else {
    score += 1;
  }

  for (final word in words) {
    if (word.length < 2) {
      score -= 2;
      continue;
    }
    final startsUpper = RegExp(r'^[A-ZÁÉÍÓÚÜÑ]').hasMatch(word);
    final allUpper = word == word.toUpperCase();
    if (startsUpper || allUpper) score += 1;
  }

  final lettersOnly = line.replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ]'), '');
  if (lettersOnly.length >= 6 && lettersOnly == lettersOnly.toUpperCase()) {
    score -= 5;
  }

  if (normalized.contains('ficha tecnica') ||
      normalized.contains('datos basicos') ||
      normalized.contains('informacion basica')) {
    score -= 8;
  }

  final topHalfLimit = (totalLines * 0.55).ceil();
  if (lineIndex <= topHalfLimit) {
    score += 1;
  } else {
    score -= 1;
  }

  return score;
}

String? _sanitizeNameCandidate(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  if (_isBoliviaDepartmentLine(trimmed) ||
      _containsBoliviaDepartmentMention(trimmed)) {
    return null;
  }
  return trimmed;
}

List<String> _tokenizeWords(String line) {
  return line
      .split(RegExp(r'\s+'))
      .map((part) => part.replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ]'), ''))
      .where((part) => part.isNotEmpty)
      .toList();
}

bool _normalizedContainsAny(String text, List<String> needles) {
  final normalized = _normalizeText(text);
  final tokens = normalized.split(RegExp(r'[^a-z0-9]+')).toSet();

  for (final needle in needles) {
    if (needle.contains(' ')) {
      if (normalized.contains(needle)) return true;
      continue;
    }
    if (tokens.contains(needle)) return true;
  }
  return false;
}

bool _isBoliviaDepartmentLine(String text) {
  final normalized = _normalizeText(text).trim();
  if (normalized.isEmpty) return false;

  final normalizedCompact = normalized
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
  if (normalizedCompact.isEmpty) return false;

  if (_boliviaDepartmentAbbreviations.contains(normalizedCompact)) {
    return true;
  }

  for (final department in _boliviaDepartments) {
    if (normalizedCompact == department) return true;
  }

  final hasDepartmentContext = _departmentContextWords.any(
    (word) => RegExp('(^|\\s)$word(\\s|\$)').hasMatch(normalizedCompact),
  );
  if (hasDepartmentContext) {
    for (final department in _boliviaDepartments) {
      if (RegExp(
        '(^|\\s)${RegExp.escape(department)}(\\s|\$)',
      ).hasMatch(normalizedCompact)) {
        return true;
      }
    }
  }

  final words = normalizedCompact.split(RegExp(r'\s+'));
  if (words.length <= 3) {
    for (final department in _boliviaDepartments) {
      if (RegExp(
        '(^|\\s)${RegExp.escape(department)}(\\s|\$)',
      ).hasMatch(normalizedCompact)) {
        return true;
      }
    }
  }
  return false;
}

bool _containsBoliviaDepartmentMention(String text) {
  final normalized = _normalizeText(text);
  final compact = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  if (compact.isEmpty) return false;

  if (_boliviaDepartmentAbbreviations.contains(compact)) return true;

  for (final department in _boliviaDepartments) {
    if (RegExp(
      '(^|\\s)${RegExp.escape(department)}(\\s|\$)',
    ).hasMatch(compact)) {
      return true;
    }
  }
  return false;
}

String _normalizeText(String text) {
  return text
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n');
}

String? _extractLikelyAddress(List<String> lines) {
  for (final line in lines) {
    final lower = line.toLowerCase();
    if (lower.contains('av') ||
        lower.contains('avenida') ||
        lower.contains('calle') ||
        lower.contains('zona') ||
        lower.contains('barrio') ||
        lower.contains('nro') ||
        lower.contains('#')) {
      return line;
    }
  }
  return null;
}

String? extractPhone(List<String> lines) {
  if (lines.isEmpty) return null;

  var bestScore = -999;
  String? bestDigits;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final hasLabel =
        _containsPhoneLabel(line) ||
        (i > 0 && _isPhoneLabelOnlyLine(lines[i - 1]));
    final hasNonPhoneContext = _normalizedContainsAny(
      line,
      _nonPhoneNumberContextWords,
    );
    final hasCountryCode = RegExp(r'\+?\s*591').hasMatch(line);
    final hasParenGrouping = line.contains('(') && line.contains(')');

    final candidates = _extractDigitCandidatesFromLine(line);
    for (final digits in candidates) {
      if (digits.length < 7) continue;
      final score = _scorePhoneCandidate(
        digits: digits,
        hasLabel: hasLabel,
        hasNonPhoneContext: hasNonPhoneContext,
        hasCountryCode: hasCountryCode,
        hasParenGrouping: hasParenGrouping,
        lineIndex: i,
        totalLines: lines.length,
      );
      if (score > bestScore) {
        bestScore = score;
        bestDigits = digits;
      }
    }
  }

  if (bestDigits != null && bestScore >= 2) return bestDigits;

  // Fallback: OCR sometimes splits digits across lines; try a combined pass.
  final combined = lines.join(' ');
  final combinedHasLabel =
      lines.any(_containsPhoneLabel) || lines.any(_isPhoneLabelOnlyLine);
  final combinedHasNonPhoneContext = lines.any(
    (line) => _normalizedContainsAny(line, _nonPhoneNumberContextWords),
  );
  final combinedHasCountryCode = RegExp(r'\+?\s*591').hasMatch(combined);
  final combinedHasParenGrouping =
      combined.contains('(') && combined.contains(')');

  final combinedCandidates = _extractDigitCandidatesFromLine(combined);
  for (final digits in combinedCandidates) {
    if (digits.length < 7) continue;
    final score = _scorePhoneCandidate(
      digits: digits,
      hasLabel: combinedHasLabel,
      hasNonPhoneContext: combinedHasNonPhoneContext,
      hasCountryCode: combinedHasCountryCode,
      hasParenGrouping: combinedHasParenGrouping,
      lineIndex: 0,
      totalLines: 1,
    );
    if (score > bestScore) {
      bestScore = score;
      bestDigits = digits;
    }
  }

  if (bestDigits == null || bestScore < 1) return null;
  return bestDigits;
}

int _scorePhoneCandidate({
  required String digits,
  required bool hasLabel,
  required bool hasNonPhoneContext,
  required bool hasCountryCode,
  required bool hasParenGrouping,
  required int lineIndex,
  required int totalLines,
}) {
  var score = 0;
  var localDigits = digits;
  if (localDigits.startsWith('591') && localDigits.length >= 10) {
    localDigits = localDigits.substring(3);
  }

  final length = localDigits.length;
  if (length == 8) {
    score += 8;
  } else if (length == 7) {
    score += 5;
  } else if (length == 9) {
    score += 2;
  } else {
    score -= 6;
  }

  if (localDigits.startsWith(RegExp(r'[67]'))) {
    score += 3;
  } else if (localDigits.startsWith(RegExp(r'[2345]'))) {
    score += 1;
  }

  if (hasCountryCode) score += 3;
  if (hasParenGrouping) score += 1;

  if (hasLabel) score += 6;
  if (hasNonPhoneContext && !hasLabel) score -= 4;

  if (RegExp(r'(\d)\1{3,}').hasMatch(localDigits)) score -= 4;
  if (RegExp(
    r'(0123|1234|2345|3456|4567|5678|8765|7654|6543|5432|4321|3210)',
  ).hasMatch(localDigits)) {
    score -= 3;
  }

  if (lineIndex <= 2) score += 1;
  if (lineIndex >= totalLines - 2) score -= 1;

  return score;
}

bool _containsPhoneLabel(String text) {
  return _normalizedContainsAny(text, _phoneLabels);
}

bool _isPhoneLabelOnlyLine(String line) {
  for (final label in _phoneLabels) {
    if (_isLikelyLabelOnlyLine(line, label)) return true;
  }
  return false;
}

List<String> _extractDigitCandidatesFromLine(String line) {
  final matches = RegExp(r'\d+').allMatches(line).toList();
  if (matches.isEmpty) return const [];

  final candidates = <String>[];
  String current = '';
  var lastEnd = -1;

  void flushCurrent() {
    if (current.length >= 7 && current.length <= 11) {
      candidates.add(current);
    }
    current = '';
    lastEnd = -1;
  }

  for (final match in matches) {
    final digits = match.group(0) ?? '';
    if (current.isEmpty) {
      current = digits;
      lastEnd = match.end;
      if (current.length >= 7 && current.length <= 11) {
        candidates.add(current);
      }
      continue;
    }

    final gap = line.substring(lastEnd, match.start);
    final gapOk = RegExp(r'^[\s().-]+$').hasMatch(gap);
    if (!gapOk) {
      flushCurrent();
      current = digits;
      lastEnd = match.end;
      if (current.length >= 7 && current.length <= 11) {
        candidates.add(current);
      }
      continue;
    }

    if (current.length + digits.length > 11) {
      flushCurrent();
      current = digits;
      lastEnd = match.end;
      if (current.length >= 7 && current.length <= 11) {
        candidates.add(current);
      }
      continue;
    }

    current += digits;
    lastEnd = match.end;
    if (current.length >= 7 && current.length <= 11) {
      candidates.add(current);
    }
  }

  if (current.isNotEmpty) {
    flushCurrent();
  }

  return candidates;
}

const List<String> _nameContextStopwords = [
  'nombre',
  'destinatario',
  'cliente',
  'ship',
  'ship to',
  'envio',
  'envío',
  'destino',
  'to',
  'campos',
  'clave',
  'ficha',
  'tecnica',
  'ficha tecnica',
  'informacion',
  'datos',
  'basicos',
  'direccion',
  'domicilio',
  'calle',
  'avenida',
  'av ',
  'zona',
  'barrio',
  'nro',
  'numero',
  'telefono',
  'celular',
  'whatsapp',
  'banco',
  'agencia',
  'central',
  'sucursal',
  'factura',
  'codigo',
  'cod',
  'detalle',
  'producto',
  'cantidad',
  'precio',
  'total',
  'nit',
  'ci',
];

const List<String> _phoneLabels = [
  'telefono',
  'tel',
  'telf',
  'cel',
  'celular',
  'whatsapp',
  'wsp',
  'movil',
];

const List<String> _addressStopwords = [
  'direccion',
  'dirección',
  'domicilio',
  'calle',
  'avenida',
  'av ',
  'zona',
  'barrio',
  'nro',
  'numero',
  'postal',
  'ciudad',
  'departamento',
];

const List<String> _nonPhoneNumberContextWords = [
  'nit',
  'ci',
  'cedula',
  'carnet',
  'codigo',
  'cod',
  'nro',
  'numero',
  'factura',
  'pedido',
  'orden',
  'serie',
  'qr',
  'barra',
  'postal',
];

const List<String> _boliviaDepartments = [
  'la paz',
  'cochabamba',
  'santa cruz',
  'oruro',
  'potosi',
  'chuquisaca',
  'tarija',
  'beni',
  'pando',
  'santa cruz de la sierra',
];

const Set<String> _boliviaDepartmentAbbreviations = {
  'lpz',
  'cbb',
  'cbba',
  'scz',
  'oru',
  'pts',
  'chq',
  'tja',
  'bni',
  'pnd',
};

const List<String> _departmentContextWords = [
  'departamento',
  'depto',
  'dpto',
  'ciudad',
  'provincia',
];
