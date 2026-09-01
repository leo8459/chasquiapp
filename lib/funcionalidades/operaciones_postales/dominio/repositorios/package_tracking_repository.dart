import 'dart:typed_data';

import '../modelos/available_couriers_result.dart';
import '../modelos/assigned_package_summary.dart';
import '../modelos/courier_inventory_packages_result.dart';
import '../modelos/package_tracking_result.dart';
import '../modelos/tracking_events_result.dart';

abstract class PackageTrackingRepository {
  const PackageTrackingRepository();

  Future<PackageTrackingResult?> findByCode(String rawCode);

  Future<TrackingEventsResult> findTrackingEventsByCode(String rawCode);

  Future<List<AssignedPackageSummary>> findAssignmentsForUser(
    int userId, {
    bool forceRefresh = false,
  });

  Future<List<AssignedPackageSummary>> findMySiopAssignedPackages();

  Future<void> assignSiopPackagesToMe(List<String> codes);

  Future<void> deliverMySiopPackage({
    required String code,
    required String description,
    required String receivedBy,
    required DateTime deliveredAt,
    required Uint8List deliveryPhotoBytes,
    required String deliveryPhotoFileName,
    required String deliveryPhotoContentType,
  });

  Future<List<AssignedPackageSummary>> findRecentRegionalAssignments();

  Future<AvailableCouriersResult> findAvailableCouriers({
    bool forceRefresh = false,
    bool allCities = false,
  });

  Future<void> preloadManagementInventory() async {}

  Future<CourierInventoryPackagesResult> findInventoryPackagesForCourier(
    int userId, {
    bool forceRefresh = false,
  });

  Future<void> assignInventoryPackages({
    required int courierUserId,
    required PackageCategory packageType,
    required List<int> packageIds,
  });

  Future<void> revertAssignmentToWarehouse({
    required int courierUserId,
    required int assignmentId,
  });

  Future<void> confirmAssignmentDelivered({
    required int assignmentId,
    required int userId,
    required String receivedBy,
    required Uint8List deliveryPhotoBytes,
    required String deliveryPhotoFileName,
    required String deliveryPhotoContentType,
    required Uint8List deliverySignatureBytes,
    required String deliverySignatureFileName,
  });

  Future<int> registerAssignmentDevolution({
    required int assignmentId,
    required int userId,
    required String description,
    required Uint8List evidencePhotoBytes,
    required String evidencePhotoFileName,
    required String evidencePhotoContentType,
  });
}
