class CourierSummary {
  const CourierSummary({
    required this.id,
    required this.name,
    required this.email,
    required this.ci,
    required this.city,
    required this.roleName,
    required this.activeAssignmentsCount,
  });

  final int id;
  final String name;
  final String email;
  final String ci;
  final String city;
  final String roleName;
  final int activeAssignmentsCount;

  String get displayName => name.isEmpty ? email : name;

  String get safeCi => ci.isEmpty ? 'Sin CI' : ci;

  String get safeCity => city.isEmpty ? 'Sin ciudad' : city;

  String get roleLabel {
    final normalized = roleName.trim();
    if (normalized.isEmpty) {
      return 'SIN ROL';
    }

    return normalized.toUpperCase().replaceAll('_', ' ');
  }

  CourierSummary copyWith({
    int? id,
    String? name,
    String? email,
    String? ci,
    String? city,
    String? roleName,
    int? activeAssignmentsCount,
  }) {
    return CourierSummary(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      ci: ci ?? this.ci,
      city: city ?? this.city,
      roleName: roleName ?? this.roleName,
      activeAssignmentsCount:
          activeAssignmentsCount ?? this.activeAssignmentsCount,
    );
  }
}
