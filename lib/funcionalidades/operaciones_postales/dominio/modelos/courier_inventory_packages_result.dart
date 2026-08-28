import 'courier_summary.dart';
import 'inventory_package_summary.dart';

class CourierInventoryPackagesResult {
  const CourierInventoryPackagesResult({
    required this.city,
    required this.courier,
    required this.packages,
  });

  final String city;
  final CourierSummary courier;
  final List<InventoryPackageSummary> packages;

  String get safeCity => city.trim().isEmpty ? 'Sin ciudad' : city.trim();
}
