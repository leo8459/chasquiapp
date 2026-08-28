import 'package:scan_agbc/nucleo/utilidades/bolivia_date_time_formatter.dart';

import 'package_tracking_result.dart';

class AssignedPackageSummary {
  const AssignedPackageSummary({
    required this.assignmentId,
    required this.code,
    required this.category,
    required this.stateName,
    required this.createdAt,
    this.courierUserId = 0,
    this.courierName = '',
  });

  final int assignmentId;
  final String code;
  final PackageCategory category;
  final String stateName;
  final DateTime? createdAt;
  final int courierUserId;
  final String courierName;

  AssignedPackageSummary copyWith({
    int? assignmentId,
    String? code,
    PackageCategory? category,
    String? stateName,
    DateTime? createdAt,
    int? courierUserId,
    String? courierName,
  }) {
    return AssignedPackageSummary(
      assignmentId: assignmentId ?? this.assignmentId,
      code: code ?? this.code,
      category: category ?? this.category,
      stateName: stateName ?? this.stateName,
      createdAt: createdAt ?? this.createdAt,
      courierUserId: courierUserId ?? this.courierUserId,
      courierName: courierName ?? this.courierName,
    );
  }

  String get safeCourierName {
    final normalized = courierName.trim();
    return normalized.isEmpty ? 'Sin cartero' : normalized;
  }

  String get formattedDate => BoliviaDateTimeFormatter.format(createdAt);
}
