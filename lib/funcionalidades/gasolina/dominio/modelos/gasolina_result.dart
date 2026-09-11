class GasolinaEntry {
  const GasolinaEntry({
    required this.id,
    required this.stationName,
    required this.totalAmount,
    required this.dateTime,
    required this.invoiceNumber,
    required this.customerName,
    required this.vehiclePlate,
    required this.driverName,
    required this.vehicleId,
    required this.driverId,
    required this.liters,
    required this.unitPrice,
    required this.status,
  });

  final int id;
  final String stationName;
  final double? totalAmount;
  final DateTime? dateTime;
  final String invoiceNumber;
  final String customerName;
  final String vehiclePlate;
  final String driverName;
  final int vehicleId;
  final int driverId;
  final double? liters;
  final double? unitPrice;
  final String status;
}

class GasolinaResult {
  const GasolinaResult({
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
  final List<GasolinaEntry> entries;
}
