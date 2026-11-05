import 'assigned_package_summary.dart';

class PendingAssignmentsSummary {
  const PendingAssignmentsSummary({
    required this.departmentName,
    required this.pendingTotal,
    required this.assignments,
  });

  final String departmentName;
  final int pendingTotal;
  final List<AssignedPackageSummary> assignments;
}
