import 'package:scan_agbc/nucleo/utilidades/bolivia_date_time_formatter.dart';

import 'package_tracking_result.dart';

class InventoryPackageSummary {
  const InventoryPackageSummary({
    required this.packageId,
    required this.packageType,
    required this.code,
    required this.recipientName,
    required this.city,
    required this.createdAt,
    this.stateName = 'VENTANILLA',
    this.attemptCount = 0,
  });

  final int packageId;
  final PackageCategory packageType;
  final String code;
  final String recipientName;
  final String city;
  final DateTime? createdAt;
  final String stateName;
  final int attemptCount;

  String get packageTypeLabel => packageType.label;

  String get safeRecipientName {
    final normalized = recipientName.trim();
    return normalized.isEmpty ? 'Sin destinatario' : normalized;
  }

  String get safeCity {
    final normalized = city.trim();
    return normalized.isEmpty ? 'Sin ciudad' : normalized;
  }

  String get formattedDate => BoliviaDateTimeFormatter.format(createdAt);

  bool get hasMaximumAttempts => attemptCount >= 3;

  String get safeStateName {
    final normalized = stateName.trim().toUpperCase();
    return normalized.isEmpty ? 'VENTANILLA' : normalized;
  }

  bool get isDevolution => safeStateName == 'DEVOLUCION';
}
