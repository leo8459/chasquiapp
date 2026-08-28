enum PackageCategory { ems, certi, contrato, ordi }

extension PackageCategoryX on PackageCategory {
  String get label {
    switch (this) {
      case PackageCategory.ems:
        return 'EMS';
      case PackageCategory.certi:
        return 'Certificado';
      case PackageCategory.contrato:
        return 'Contrato';
      case PackageCategory.ordi:
        return 'Ordinario';
    }
  }

  String get tableName {
    switch (this) {
      case PackageCategory.ems:
        return 'paquetes_ems';
      case PackageCategory.certi:
        return 'paquetes_certi';
      case PackageCategory.contrato:
        return 'paquetes_contrato';
      case PackageCategory.ordi:
        return 'paquetes_ordi';
    }
  }
}

PackageCategory? packageCategoryFromName(String raw) {
  final normalized = raw.trim().toLowerCase();
  switch (normalized) {
    case 'ems':
      return PackageCategory.ems;
    case 'certi':
    case 'certificado':
      return PackageCategory.certi;
    case 'contrato':
      return PackageCategory.contrato;
    case 'ordi':
    case 'ordinario':
      return PackageCategory.ordi;
    default:
      return null;
  }
}

class PackageTrackingResult {
  const PackageTrackingResult({
    required this.code,
    required this.category,
    required this.highlightLocation,
    required this.locationNote,
    required this.city,
    required this.province,
    required this.recipientName,
    required this.phone,
    required this.weight,
    required this.detail,
    this.packageId = 0,
    this.stateName = '',
    this.attemptCount = 0,
    this.assignedCourierName = '',
  });

  final String code;
  final PackageCategory category;
  final String highlightLocation;
  final String locationNote;
  final String city;
  final String province;
  final String recipientName;
  final String phone;
  final String weight;
  final String detail;
  final int packageId;
  final String stateName;
  final int attemptCount;
  final String assignedCourierName;

  String get safeHighlightLocation {
    return highlightLocation.trim();
  }

  bool get hasHighlightLocation =>
      safeHighlightLocation.isNotEmpty && !hasMissingLocation;

  bool get hasMissingLocation {
    final normalizedLocation = safeHighlightLocation.toUpperCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    return locationNote.trim().isNotEmpty ||
        normalizedLocation == 'SIN DIRECCION' ||
        normalizedLocation == 'SIN DIRECCION REGISTRADA' ||
        normalizedLocation == 'DIRECCION NO REGISTRADA';
  }

  bool get hasLocationNote => hasMissingLocation;

  String get safeLocationNote => locationNote.trim();

  String get safeCity => city.isEmpty ? 'Sin dato' : city;

  bool get hasProvince => province.trim().isNotEmpty;

  String get safeProvince => hasProvince ? province.trim() : 'Sin dato';

  String get safeRecipientName =>
      recipientName.isEmpty ? 'Sin destinatario' : recipientName;

  String get safePhone => phone.isEmpty ? 'Sin teléfono' : phone;

  String get safeWeight => weight.isEmpty ? 'Sin peso' : weight;

  String get safeDetail => detail.isEmpty ? 'Sin contenido o tipo' : detail;

  bool get hasAssignmentStatus =>
      stateName.trim().isNotEmpty || attemptCount > 0;

  String get safeStateName =>
      stateName.trim().isEmpty ? 'Sin estado' : stateName.trim();

  bool get hasAssignedCourier => assignedCourierName.trim().isNotEmpty;

  String get safeAssignedCourierName =>
      hasAssignedCourier ? assignedCourierName.trim() : 'Sin cartero asignado';
}
