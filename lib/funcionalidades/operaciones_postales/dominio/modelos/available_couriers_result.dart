import 'courier_summary.dart';

class AvailableCouriersResult {
  const AvailableCouriersResult({required this.city, required this.couriers});

  final String city;
  final List<CourierSummary> couriers;

  int get total => couriers.length;

  String get safeCity => city.trim().isEmpty ? 'Sin ciudad' : city.trim();
}
