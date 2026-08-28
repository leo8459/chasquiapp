enum UserRoleAccessProfile { clasificaciones, carteros, gestion, consulta }

class UserRolePermissions {
  UserRolePermissions._(this.roles);

  factory UserRolePermissions.fromRoles(Set<String> rawRoles) {
    return UserRolePermissions._(
      rawRoles
          .map((role) => role.trim().toLowerCase())
          .where((role) => role.isNotEmpty)
          .toSet(),
    );
  }

  static final RegExp _courierRolePattern = RegExp(r'cartero');
  static final RegExp _auxiliarRolePattern = RegExp(r'auxiliar');
  static final RegExp _encargadoRolePattern = RegExp(r'encargado');
  static const String _tratamientoRole = 'tratamiento';
  static const String _auxiliarTratamientoRole = 'auxiliar_tratamiento';
  static const String _encargadoEmsRole = 'encargado_ems';
  static const String _administratorRole = 'administrador';

  final Set<String> roles;

  bool get isAdministrator => roles.contains(_administratorRole);

  bool get hasRecognizedRole => roles.any(_isRecognizedRole);

  bool get hasClassificationRole => roles.any(_matchesClassificationRole);

  bool get hasCourierRole => roles.any(_matchesCourierRole);

  bool get hasEncargadoRole =>
      roles.any((role) => _encargadoRolePattern.hasMatch(role));

  bool get hasEmsManagementRole =>
      roles.contains(_encargadoEmsRole) ||
      roles.contains('73') ||
      roles.contains('role_73') ||
      roles.contains('id_rol_73');

  bool get hasSelfAssignableManagementRole => hasEmsManagementRole;

  bool get hasManagementRole =>
      isAdministrator || hasEncargadoRole || hasSelfAssignableManagementRole;

  bool get canChooseOperationalMode =>
      isAdministrator ||
      (hasManagementRole && hasCourierRole) ||
      hasSelfAssignableManagementRole;

  UserRoleAccessProfile get accessProfile {
    if (hasClassificationRole) {
      return UserRoleAccessProfile.clasificaciones;
    }
    if (hasManagementRole) {
      return UserRoleAccessProfile.gestion;
    }
    if (hasCourierRole) {
      return UserRoleAccessProfile.carteros;
    }
    return UserRoleAccessProfile.consulta;
  }

  bool get canSearchPackages {
    if (isAdministrator) return true;
    if (!hasRecognizedRole) return false;
    return accessProfile == UserRoleAccessProfile.carteros ||
        accessProfile == UserRoleAccessProfile.gestion;
  }

  bool get canViewOwnAssignments =>
      isAdministrator ||
      accessProfile == UserRoleAccessProfile.carteros ||
      hasSelfAssignableManagementRole ||
      (hasManagementRole && hasCourierRole);

  bool get canSearchCourierByCi =>
      isAdministrator || accessProfile == UserRoleAccessProfile.gestion;

  bool get canRegisterPackages =>
      isAdministrator || accessProfile == UserRoleAccessProfile.clasificaciones;

  bool _isRecognizedRole(String role) {
    return _matchesClassificationRole(role) ||
        _matchesCourierRole(role) ||
        role == _administratorRole ||
        _encargadoRolePattern.hasMatch(role) ||
        _matchesSelfAssignableManagementMarker(role);
  }

  bool _matchesClassificationRole(String role) {
    return role == _tratamientoRole || role == _auxiliarTratamientoRole;
  }

  bool _matchesCourierRole(String role) {
    if (role == _auxiliarTratamientoRole) {
      return false;
    }

    return _courierRolePattern.hasMatch(role) ||
        _auxiliarRolePattern.hasMatch(role);
  }

  bool _matchesSelfAssignableManagementMarker(String role) {
    return role == _encargadoEmsRole ||
        role == '73' ||
        role == 'role_73' ||
        role == 'id_rol_73';
  }
}
