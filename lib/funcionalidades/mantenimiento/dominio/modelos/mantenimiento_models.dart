class MantenimientoEntry {
  const MantenimientoEntry({
    required this.id,
    required this.vehicleId,
    required this.vehiclePlate,
    required this.vehicleName,
    required this.maintenanceTypeId,
    required this.maintenanceType,
    required this.scheduledAt,
    required this.status,
    required this.description,
    required this.createdAt,
  });

  final int id;
  final int vehicleId;
  final String vehiclePlate;
  final String vehicleName;
  final int maintenanceTypeId;
  final String maintenanceType;
  final DateTime? scheduledAt;
  final String status;
  final String description;
  final DateTime? createdAt;
}

class MantenimientoResult {
  const MantenimientoResult({
    required this.currentPage,
    required this.lastPage,
    required this.perPage,
    required this.total,
    required this.entries,
  });

  final int currentPage;
  final int lastPage;
  final int perPage;
  final int total;
  final List<MantenimientoEntry> entries;
}

class MantenimientoVehicle {
  const MantenimientoVehicle({
    required this.id,
    required this.plate,
    required this.name,
    required this.available,
  });

  final int id;
  final String plate;
  final String name;
  final bool available;

  String get label => name.isEmpty ? plate : '$plate · $name';
}

class MantenimientoType {
  const MantenimientoType({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
  });

  final int id;
  final String name;
  final String category;
  final String description;
}

class MantenimientoOptions {
  const MantenimientoOptions({required this.vehicles, required this.types});

  final List<MantenimientoVehicle> vehicles;
  final List<MantenimientoType> types;
}
