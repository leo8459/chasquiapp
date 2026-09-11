class BitacoraEntry {
  const BitacoraEntry({
    required this.id,
    required this.date,
    required this.startMileage,
    required this.arrivalMileage,
    required this.traveledMileage,
    required this.startLocation,
    required this.destinationLocation,
    required this.fueled,
    required this.active,
    required this.packageCount,
    required this.sessionReference,
    required this.driverId,
    required this.driverName,
    required this.driverPhone,
    required this.driverEmail,
    required this.vehiclePlate,
    required this.vehicleId,
    required this.vehicleBrand,
    required this.vehicleModel,
    required this.vehicleColor,
    required this.vehicleYear,
  });

  final int id;
  final DateTime? date;
  final double? startMileage;
  final double? arrivalMileage;
  final double? traveledMileage;
  final String startLocation;
  final String destinationLocation;
  final bool fueled;
  final bool active;
  final int? packageCount;
  final String sessionReference;
  final int driverId;
  final String driverName;
  final String driverPhone;
  final String driverEmail;
  final String vehiclePlate;
  final int vehicleId;
  final String vehicleBrand;
  final String vehicleModel;
  final String vehicleColor;
  final int? vehicleYear;

  double? get resolvedTraveledMileage {
    if (traveledMileage != null) return traveledMileage;
    if (startMileage == null || arrivalMileage == null) return null;
    return arrivalMileage! - startMileage!;
  }
}

class BitacoraResult {
  const BitacoraResult({
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
  final List<BitacoraEntry> entries;
}
