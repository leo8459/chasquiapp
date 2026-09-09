import 'dart:async';
import 'dart:convert';

import 'package:scan_agbc/nucleo/red/api_client.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/available_couriers_result.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/assigned_package_summary.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/courier_inventory_packages_result.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/contract_package_pickup_result.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/courier_summary.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/inventory_package_summary.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/package_tracking_result.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/tracking_events_result.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/repositorios/package_tracking_repository.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/utilidades/package_code_classifier.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/utilidades/delivery_recipient_name_validator.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int _cachedJsonIsolateDecodeThreshold = 48 * 1024;

Map<String, dynamic>? _decodeCachedJsonMap(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }
  if (decoded is Map) {
    return Map<String, dynamic>.from(decoded);
  }
  return null;
}

class ApiPackageTrackingRepository extends PackageTrackingRepository {
  ApiPackageTrackingRepository(this._client);

  final ApiClient _client;
  AvailableCouriersResult? _availableCouriersMemoryCache;
  Future<AvailableCouriersResult>? _availableCouriersInFlight;
  final Map<int, List<AssignedPackageSummary>> _assignmentsMemoryCache =
      <int, List<AssignedPackageSummary>>{};
  final Map<int, Future<List<AssignedPackageSummary>>> _assignmentsInFlight =
      <int, Future<List<AssignedPackageSummary>>>{};
  final Map<int, CourierInventoryPackagesResult> _inventoryMemoryCache =
      <int, CourierInventoryPackagesResult>{};
  final Map<int, Future<CourierInventoryPackagesResult>> _inventoryInFlight =
      <int, Future<CourierInventoryPackagesResult>>{};
  final Map<String, List<InventoryPackageSummary>>
  _regionalInventoryMemoryCache = <String, List<InventoryPackageSummary>>{};
  Future<void>? _managementInventoryPreloadInFlight;

  void _invalidateCourierPackages(int courierUserId) {
    _assignmentsMemoryCache.remove(courierUserId);
    _assignmentsInFlight.remove(courierUserId);
    _inventoryMemoryCache.clear();
    _inventoryInFlight.clear();
    _regionalInventoryMemoryCache.clear();
  }

  void _applyCourierMutationPayload(
    int courierUserId,
    Map<String, dynamic> payload,
  ) {
    _invalidateCourierPackages(courierUserId);

    final payloadCourierUserId = _toInt(payload['courier_user_id']);
    final resolvedCourierUserId = payloadCourierUserId > 0
        ? payloadCourierUserId
        : courierUserId;
    final nextCount = _toNullableInt(payload['active_assignments_count']);
    if (resolvedCourierUserId <= 0 || nextCount == null) {
      _availableCouriersMemoryCache = null;
      _availableCouriersInFlight = null;
      return;
    }

    final cachedCouriers = _availableCouriersMemoryCache;
    if (cachedCouriers == null) {
      return;
    }

    var patched = false;
    final couriers = cachedCouriers.couriers
        .map((courier) {
          if (courier.id != resolvedCourierUserId) {
            return courier;
          }
          patched = true;
          return courier.copyWith(activeAssignmentsCount: nextCount);
        })
        .toList(growable: false);

    if (!patched) {
      _availableCouriersMemoryCache = null;
      _availableCouriersInFlight = null;
      return;
    }

    _availableCouriersMemoryCache = AvailableCouriersResult(
      city: cachedCouriers.city,
      couriers: couriers,
    );
  }

  void clearMemoryCache() {
    _assignmentsMemoryCache.clear();
    _assignmentsInFlight.clear();
    _inventoryMemoryCache.clear();
    _inventoryInFlight.clear();
    _regionalInventoryMemoryCache.clear();
    _managementInventoryPreloadInFlight = null;
    _availableCouriersMemoryCache = null;
    _availableCouriersInFlight = null;
  }

  static const String _assignmentsCachePrefix =
      'package_tracking_assignments_cache_v1';
  static const String _inventoryCachePrefix =
      'package_tracking_inventory_cache_v2';
  static const String _legacyInventoryCachePrefix =
      'package_tracking_inventory_cache_v1';
  static const String _cacheSavedAtSuffix = '_saved_at';
  static const Duration _diskCacheTtl = Duration(hours: 4);

  @override
  Future<PackageTrackingResult?> findByCode(String rawCode) async {
    final plan = PackageCodeClassifier.build(rawCode);
    if (plan.normalizedCode.isEmpty) {
      return null;
    }

    try {
      final payload = await _client.getJsonMap(
        '/mobile/tracking/package',
        queryParameters: {'code': plan.normalizedCode},
        authorize: true,
      );
      final found = payload['found'] == true;
      if (!found) {
        return null;
      }

      final category = _resolveCategory(
        rawCategory: payload['package_type']?.toString() ?? '',
        fallbackCode: plan.normalizedCode,
      );
      if (category == null) {
        return null;
      }

      return PackageTrackingResult(
        code: plan.normalizedCode,
        category: category,
        highlightLocation:
            payload['highlight_location']?.toString().trim() ?? '',
        locationNote: payload['location_note']?.toString().trim() ?? '',
        city: payload['city']?.toString().trim() ?? '',
        province: payload['province']?.toString().trim() ?? '',
        recipientName: payload['recipient_name']?.toString().trim() ?? '',
        phone: payload['phone']?.toString().trim() ?? '',
        weight: payload['weight']?.toString().trim() ?? '',
        detail:
            payload['detail']?.toString().trim() ??
            payload['package_detail']?.toString().trim() ??
            '',
        stateName: payload['state_name']?.toString().trim() ?? '',
        packageId: _toInt(payload['package_id']),
        attemptCount: _toInt(payload['attempt_count']),
        assignedCourierName:
            payload['assigned_courier_name']?.toString().trim() ?? '',
      );
    } on ApiException catch (error) {
      if (error.statusCode == 404) {
        return null;
      }
      throw StateError(error.message);
    }
  }

  @override
  Future<TrackingEventsResult> findTrackingEventsByCode(String rawCode) async {
    final plan = PackageCodeClassifier.build(rawCode);
    if (plan.normalizedCode.isEmpty) {
      throw StateError('Ingresa un código válido para rastrear.');
    }

    try {
      final payload = await _client.getJsonMap(
        '/mobile/tracking/events',
        queryParameters: {'code': plan.normalizedCode},
        authorize: true,
      );

      final filter = payload['filtro'];
      final normalizedFilter = filter is Map
          ? filter.map((key, value) => MapEntry(key.toString(), value))
          : const <String, dynamic>{};
      final rawEvents = payload['data'];
      final events = rawEvents is List
          ? rawEvents
                .map((item) => _mapTrackingEvent(item))
                .whereType<TrackingEventSummary>()
                .toList(growable: false)
          : const <TrackingEventSummary>[];

      return TrackingEventsResult(
        code:
            normalizedFilter['codigo']?.toString().trim() ??
            plan.normalizedCode,
        table: normalizedFilter['tabla']?.toString().trim() ?? '',
        exact: normalizedFilter['exacto'] == true,
        limit: _toInt(normalizedFilter['limit']),
        total: _toInt(payload['total']),
        events: events,
      );
    } on ApiException catch (error) {
      throw StateError(error.message);
    }
  }

  @override
  Future<List<AssignedPackageSummary>> findAssignmentsForUser(
    int userId, {
    bool forceRefresh = false,
  }) async {
    if (userId <= 0) {
      return const <AssignedPackageSummary>[];
    }

    if (!forceRefresh) {
      final cached = _assignmentsMemoryCache[userId];
      if (cached != null) {
        return cached;
      }
    }

    final inFlight = _assignmentsInFlight[userId];
    if (inFlight != null) {
      return inFlight;
    }

    final future = _findAssignmentsForUserFromApi(userId);
    _assignmentsInFlight[userId] = future;
    try {
      final result = await future;
      _assignmentsMemoryCache[userId] = result;
      return result;
    } finally {
      if (identical(_assignmentsInFlight[userId], future)) {
        _assignmentsInFlight.remove(userId);
      }
    }
  }

  @override
  Future<List<AssignedPackageSummary>> findMySiopAssignedPackages() async {
    try {
      final payload = await _client.getJsonMap(
        '/mobile/courier/assigned-packages',
        authorize: true,
      );
      final assignments = payload['assignments'];
      if (assignments is! List) {
        return const <AssignedPackageSummary>[];
      }

      return assignments
          .map((item) => _mapAssignment(item))
          .whereType<AssignedPackageSummary>()
          .toList(growable: false);
    } on ApiException catch (error) {
      throw StateError(error.message);
    }
  }

  @override
  Future<void> assignSiopPackagesToMe(List<String> codes) async {
    final normalizedCodes = codes
        .map(PackageCodeClassifier.normalize)
        .where((code) => code.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalizedCodes.isEmpty) {
      throw StateError('Selecciona al menos un paquete válido.');
    }

    try {
      await _client.postJsonMap(
        '/mobile/courier/assign-packages',
        authorize: true,
        body: {'codes': normalizedCodes},
      );
    } on ApiException catch (error) {
      throw StateError(error.message);
    }
  }

  @override
  Future<ContractPackagePickupResult> pickupContractPackages(
    Map<String, double> weightsByCode,
  ) async {
    final normalizedShipments = <String, double>{};
    for (final entry in weightsByCode.entries) {
      final code = PackageCodeClassifier.normalize(entry.key);
      if (code.isNotEmpty) normalizedShipments[code] = entry.value;
    }
    if (normalizedShipments.isEmpty) {
      throw StateError('Selecciona al menos un paquete válido.');
    }
    if (normalizedShipments.values.any(
      (weight) => weight < 0.001 || weight > 150,
    )) {
      throw StateError('El peso debe estar entre 0,001 y 150,000 kg.');
    }

    try {
      final payload = await _client.postJsonMap(
        '/mobile/courier/pickup-contract-packages',
        authorize: true,
        body: {
          'shipments': normalizedShipments.entries
              .map((entry) => {'code': entry.key, 'weight': entry.value})
              .toList(growable: false),
        },
      );
      return ContractPackagePickupResult(
        pickedUpCount: _toInt(payload['picked_up_count']),
        codes: _stringList(payload['codes']),
        unprocessedCodes: _stringList(payload['unprocessed_codes']),
        message: payload['message']?.toString().trim() ?? '',
      );
    } on ApiException catch (error) {
      throw StateError(error.message);
    }
  }

  @override
  Future<void> deliverMySiopPackage({
    required String code,
    required String description,
    required String receivedBy,
    required DateTime deliveredAt,
    required Uint8List deliveryPhotoBytes,
    required String deliveryPhotoFileName,
    required String deliveryPhotoContentType,
  }) async {
    final validation = PackageCodeClassifier.validateForSearch(code);
    if (!validation.isValid) {
      throw StateError(
        validation.errorMessage ?? 'Selecciona un paquete valido.',
      );
    }
    final receivedByValidation = DeliveryRecipientNameValidator.validate(
      receivedBy,
    );
    if (!receivedByValidation.isValid) {
      throw StateError(
        receivedByValidation.errorMessage ??
            'Escribe quien recibio el paquete.',
      );
    }
    if (deliveryPhotoBytes.isEmpty) {
      throw StateError('Debes tomar una foto para confirmar la entrega.');
    }

    try {
      await _client.postMultipartMap(
        '/mobile/courier/deliver-package',
        authorize: true,
        fields: {
          'code': validation.normalizedCode,
          'description': description.trim(),
          'received_by': receivedByValidation.normalizedValue,
          // SIOP espera el valor de un datetime-local: YYYY-MM-DDTHH:mm,
          // sin segundos ni desplazamiento de zona horaria.
          'delivered_at': _formatDeliveryDateTime(deliveredAt),
        },
        fileField: 'delivery_photo',
        fileBytes: deliveryPhotoBytes,
        fileName: deliveryPhotoFileName,
        contentType: deliveryPhotoContentType,
      );
    } on ApiException catch (error) {
      throw StateError(error.message);
    }
  }

  String _formatDeliveryDateTime(DateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    final local = value.toLocal();
    return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)}T'
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }

  Future<List<AssignedPackageSummary>> _findAssignmentsForUserFromApi(
    int userId,
  ) async {
    try {
      final payload = await _getJsonMapWithCache(
        path: '/mobile/couriers/$userId/assignments',
        cacheKey: '${_assignmentsCachePrefix}_$userId',
      );
      final assignments = payload['assignments'];
      if (assignments is! List) {
        return const <AssignedPackageSummary>[];
      }

      return assignments
          .map((item) => _mapAssignment(item))
          .whereType<AssignedPackageSummary>()
          .toList(growable: false);
    } on ApiException catch (error) {
      throw StateError(error.message);
    }
  }

  @override
  Future<AvailableCouriersResult> findAvailableCouriers({
    bool forceRefresh = false,
    bool allCities = false,
  }) async {
    if (allCities) {
      return _findAvailableCouriersFromApi(allCities: true);
    }

    if (!forceRefresh) {
      final cached = _availableCouriersMemoryCache;
      if (cached != null) {
        return cached;
      }
    }
    final inFlight = _availableCouriersInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _findAvailableCouriersFromApi();
    _availableCouriersInFlight = future;
    try {
      final result = await future;
      _availableCouriersMemoryCache = result;
      return result;
    } finally {
      if (identical(_availableCouriersInFlight, future)) {
        _availableCouriersInFlight = null;
      }
    }
  }

  Future<AvailableCouriersResult> _findAvailableCouriersFromApi({
    bool allCities = false,
  }) async {
    try {
      final payload = await _client.getJsonMap(
        '/mobile/couriers',
        queryParameters: allCities ? const {'scope': 'all'} : null,
        authorize: true,
      );
      final city = payload['city']?.toString().trim() ?? '';
      final couriers = payload['couriers'];
      if (couriers is! List) {
        return AvailableCouriersResult(
          city: city,
          couriers: const <CourierSummary>[],
        );
      }

      return AvailableCouriersResult(
        city: city,
        couriers: couriers
            .map((item) => _mapCourier(item))
            .whereType<CourierSummary>()
            .toList(growable: false),
      );
    } on ApiException catch (error) {
      throw StateError(error.message);
    }
  }

  @override
  Future<void> preloadManagementInventory() async {
    final inFlight = _managementInventoryPreloadInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _preloadManagementInventory();
    _managementInventoryPreloadInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_managementInventoryPreloadInFlight, future)) {
        _managementInventoryPreloadInFlight = null;
      }
    }
  }

  Future<void> _preloadManagementInventory() async {
    try {
      final result = await findAvailableCouriers();
      if (result.couriers.isEmpty) return;
      await findInventoryPackagesForCourier(result.couriers.first.id);
    } catch (_) {
      // Preloading is best-effort and must never block the management home.
    }
  }

  @override
  Future<CourierInventoryPackagesResult> findInventoryPackagesForCourier(
    int userId, {
    bool forceRefresh = false,
  }) async {
    if (userId <= 0) {
      throw StateError('No se pudo identificar al cartero seleccionado.');
    }

    if (!forceRefresh) {
      final cached = _inventoryMemoryCache[userId];
      if (cached != null) {
        return cached;
      }
    }

    final inFlight = _inventoryInFlight[userId];
    if (inFlight != null) {
      return inFlight;
    }

    final future =
        (!forceRefresh
            ? _findInventoryPackagesForCourierFromRegionalCache(userId)
            : null) ??
        _findInventoryPackagesForCourierFromApi(userId);
    _inventoryInFlight[userId] = future;
    try {
      final result = await future;
      _inventoryMemoryCache[userId] = result;
      _cacheRegionalInventory(result);
      return result;
    } finally {
      if (identical(_inventoryInFlight[userId], future)) {
        _inventoryInFlight.remove(userId);
      }
    }
  }

  Future<CourierInventoryPackagesResult>?
  _findInventoryPackagesForCourierFromRegionalCache(int userId) {
    final availableCouriers = _availableCouriersMemoryCache;
    if (availableCouriers == null) return null;

    CourierSummary? courier;
    for (final candidate in availableCouriers.couriers) {
      if (candidate.id == userId) {
        courier = candidate;
        break;
      }
    }
    if (courier == null) return null;

    final city = courier.city.trim().isEmpty
        ? availableCouriers.city
        : courier.city;
    final packages = _regionalInventoryMemoryCache[_normalizeCityKey(city)];
    if (packages == null) return null;

    return Future<CourierInventoryPackagesResult>.value(
      CourierInventoryPackagesResult(
        city: city,
        courier: courier,
        packages: packages,
      ),
    );
  }

  void _cacheRegionalInventory(CourierInventoryPackagesResult result) {
    final cityKey = _normalizeCityKey(result.city);
    if (cityKey.isEmpty) return;
    _regionalInventoryMemoryCache[cityKey] = result.packages;
  }

  String _normalizeCityKey(String city) => city.trim().toUpperCase();

  Future<CourierInventoryPackagesResult>
  _findInventoryPackagesForCourierFromApi(int userId) async {
    try {
      final payload = await _getJsonMapWithCache(
        path: '/mobile/couriers/$userId/inventory-packages',
        cacheKey: '${_inventoryCachePrefix}_$userId',
      );
      final city = payload['city']?.toString().trim() ?? '';
      final courier = _mapCourier(payload['courier']);
      if (courier == null) {
        throw StateError('No se pudo recuperar el cartero seleccionado.');
      }

      final rawPackages = payload['packages'];
      final packages = rawPackages is List
          ? rawPackages
                .map((item) => _mapInventoryPackage(item))
                .whereType<InventoryPackageSummary>()
                .toList(growable: false)
          : const <InventoryPackageSummary>[];
      return CourierInventoryPackagesResult(
        city: city,
        courier: courier,
        packages: packages,
      );
    } on ApiException catch (error) {
      throw StateError(error.message);
    }
  }

  @override
  Future<void> assignInventoryPackages({
    required int courierUserId,
    required PackageCategory packageType,
    required List<int> packageIds,
  }) async {
    if (courierUserId <= 0) {
      throw StateError('No se pudo identificar al cartero seleccionado.');
    }
    final normalizedPackageIds = packageIds
        .where((id) => id > 0)
        .toList(growable: false);
    if (normalizedPackageIds.isEmpty) {
      throw StateError('Debes seleccionar un paquete válido.');
    }

    try {
      final payload = await _client.postJsonMap(
        '/mobile/couriers/$courierUserId/inventory-packages/assign',
        authorize: true,
        body: {
          'package_type': packageType.name,
          if (normalizedPackageIds.length == 1)
            'package_id': normalizedPackageIds.first,
          'package_ids': normalizedPackageIds,
        },
      );
      _applyCourierMutationPayload(courierUserId, payload);
    } on ApiException catch (error) {
      throw StateError(error.message);
    }
  }

  @override
  Future<List<AssignedPackageSummary>> findRecentRegionalAssignments() async {
    try {
      final payload = await _client.getJsonMap(
        '/mobile/couriers/assignments/recent',
        authorize: true,
      );
      final assignments = payload['assignments'];
      if (assignments is! List) {
        return const <AssignedPackageSummary>[];
      }

      return assignments
          .map((item) => _mapAssignment(item))
          .whereType<AssignedPackageSummary>()
          .toList(growable: false);
    } on ApiException catch (error) {
      throw StateError(error.message);
    }
  }

  @override
  Future<void> revertAssignmentToWarehouse({
    required int courierUserId,
    required int assignmentId,
  }) async {
    if (courierUserId <= 0) {
      throw StateError('No se pudo identificar al cartero seleccionado.');
    }
    if (assignmentId <= 0) {
      throw StateError('No se pudo identificar la asignación a revertir.');
    }

    try {
      final payload = await _client.postJsonMap(
        '/mobile/couriers/$courierUserId/assignments/$assignmentId/revert-to-warehouse',
        authorize: true,
        body: const <String, Object?>{},
      );
      _applyCourierMutationPayload(courierUserId, payload);
    } on ApiException catch (error) {
      throw StateError(error.message);
    }
  }

  CourierSummary? _mapCourier(dynamic item) {
    if (item is! Map) {
      return null;
    }

    final id = _toInt(item['id']);
    final name = item['name']?.toString().trim() ?? '';
    final email = item['email']?.toString().trim() ?? '';
    final ci = item['ci']?.toString().trim() ?? '';
    final city = item['city']?.toString().trim() ?? '';
    final roleName = item['role_name']?.toString().trim() ?? '';
    final activeAssignmentsCount = _toInt(item['active_assignments_count']);

    if (id <= 0 || (name.isEmpty && email.isEmpty)) {
      return null;
    }

    return CourierSummary(
      id: id,
      name: name,
      email: email,
      ci: ci,
      city: city,
      roleName: roleName,
      activeAssignmentsCount: activeAssignmentsCount,
    );
  }

  InventoryPackageSummary? _mapInventoryPackage(dynamic item) {
    if (item is! Map) {
      return null;
    }

    final packageId = _toInt(item['package_id']);
    final packageType = packageCategoryFromName(
      item['package_type']?.toString().trim() ?? '',
    );
    final code = item['code']?.toString().trim() ?? '';
    final recipientName = item['recipient_name']?.toString().trim() ?? '';
    final city = item['city']?.toString().trim() ?? '';
    final stateName = item['state_name']?.toString().trim() ?? '';
    final rawCreatedAt = item['created_at']?.toString().trim() ?? '';
    final attemptCount = _toInt(item['attempt_count']);

    if (packageId <= 0 || packageType == null || code.isEmpty) {
      return null;
    }

    DateTime? createdAt;
    if (rawCreatedAt.isNotEmpty) {
      createdAt = DateTime.tryParse(rawCreatedAt);
    }

    return InventoryPackageSummary(
      packageId: packageId,
      packageType: packageType,
      code: code,
      recipientName: recipientName,
      city: city,
      createdAt: createdAt,
      stateName: stateName,
      attemptCount: attemptCount,
    );
  }

  @override
  Future<void> confirmAssignmentDelivered({
    required int assignmentId,
    required int userId,
    required String receivedBy,
    required Uint8List deliveryPhotoBytes,
    required String deliveryPhotoFileName,
    required String deliveryPhotoContentType,
    required Uint8List deliverySignatureBytes,
    required String deliverySignatureFileName,
  }) async {
    if (assignmentId <= 0) {
      throw StateError('No se encontró la asignación a actualizar.');
    }
    if (userId <= 0) {
      throw StateError('No se pudo identificar al cartero.');
    }
    final receivedByValidation = DeliveryRecipientNameValidator.validate(
      receivedBy,
    );
    if (!receivedByValidation.isValid) {
      throw StateError(
        receivedByValidation.errorMessage ??
            'Escribe un nombre válido para quien recibe el paquete.',
      );
    }
    if (deliveryPhotoBytes.isEmpty) {
      throw StateError('Debes tomar una foto para confirmar la entrega.');
    }
    if (deliverySignatureBytes.isEmpty) {
      throw StateError('Debes registrar la firma de quien recibe el paquete.');
    }

    try {
      final payload = await _client.postMultipartMap(
        '/mobile/assignments/$assignmentId/deliver',
        authorize: true,
        fields: {
          'user_id': '$userId',
          'received_by': receivedByValidation.normalizedValue,
        },
        fileField: 'delivery_photo',
        fileBytes: deliveryPhotoBytes,
        fileName: deliveryPhotoFileName,
        contentType: deliveryPhotoContentType,
        extraFiles: <ApiMultipartFile>[
          ApiMultipartFile(
            fieldName: 'delivery_signature',
            fileBytes: deliverySignatureBytes,
            fileName: deliverySignatureFileName,
            contentType: 'image/png',
          ),
        ],
      );
      _applyCourierMutationPayload(userId, payload);
    } on ApiException catch (error) {
      throw StateError(error.message);
    }
  }

  @override
  Future<int> registerAssignmentDevolution({
    required int assignmentId,
    required int userId,
    required String description,
    required Uint8List evidencePhotoBytes,
    required String evidencePhotoFileName,
    required String evidencePhotoContentType,
  }) async {
    if (assignmentId <= 0) {
      throw StateError('No se encontró la asignación a actualizar.');
    }
    if (userId <= 0) {
      throw StateError('No se pudo identificar al cartero.');
    }
    final normalizedDescription = description.trim();
    if (normalizedDescription.isEmpty) {
      throw StateError(
        'Debes describir lo ocurrido para registrar la devolución.',
      );
    }
    if (evidencePhotoBytes.isEmpty) {
      throw StateError(
        'Debes tomar una foto de evidencia para registrar la devolución.',
      );
    }

    try {
      final payload = await _client.postMultipartMap(
        '/mobile/assignments/$assignmentId/devolution',
        authorize: true,
        fields: {'user_id': '$userId', 'description': normalizedDescription},
        fileField: 'delivery_attempt_photo',
        fileBytes: evidencePhotoBytes,
        fileName: evidencePhotoFileName,
        contentType: evidencePhotoContentType,
      );
      _applyCourierMutationPayload(userId, payload);
      return _toInt(payload['attempt_count']);
    } on ApiException catch (error) {
      throw StateError(error.message);
    }
  }

  AssignedPackageSummary? _mapAssignment(dynamic item) {
    if (item is! Map) {
      return null;
    }

    final packageType = item['package_type']?.toString().trim() ?? '';
    final category = packageType.toLowerCase() == 'solicitud'
        ? PackageCategory.ems
        : packageCategoryFromName(packageType);
    if (category == null) {
      return null;
    }

    final assignmentId = _toInt(item['assignment_id']);
    final code = item['code']?.toString().trim() ?? '';
    final stateName = _normalizeAssignmentStateName(
      item['state_name']?.toString() ?? '',
    );
    if (assignmentId <= 0 || code.isEmpty || stateName.isEmpty) {
      return null;
    }

    DateTime? createdAt;
    final rawCreatedAt = item['created_at']?.toString().trim() ?? '';
    if (rawCreatedAt.isNotEmpty) {
      createdAt = DateTime.tryParse(rawCreatedAt);
    }

    return AssignedPackageSummary(
      assignmentId: assignmentId,
      code: code,
      category: category,
      stateName: stateName,
      createdAt: createdAt,
      courierUserId: _toInt(item['courier_user_id']),
      courierName: item['courier_name']?.toString().trim() ?? '',
      recipientName: item['recipient_name']?.toString().trim() ?? '',
      recipientPhone: item['recipient_phone']?.toString().trim() ?? '',
      recipientAddress: item['recipient_address']?.toString().trim() ?? '',
      packageTypeLabel: packageType,
    );
  }

  String _normalizeAssignmentStateName(String rawStateName) {
    final trimmed = rawStateName.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final normalized = trimmed.toUpperCase();
    if (normalized.contains('ENTREGADO')) {
      return 'ENTREGADO';
    }

    if (normalized.contains('ASIGNADO') ||
        normalized.contains('CARTERO') ||
        normalized.contains('DOMICILIO') ||
        normalized.contains('EN PROGRESO') ||
        normalized.contains('PROGRESO')) {
      return 'CARTERO';
    }

    return trimmed;
  }

  TrackingEventSummary? _mapTrackingEvent(dynamic item) {
    if (item is! Map) {
      return null;
    }

    final code = item['codigo']?.toString().trim() ?? '';
    final event = item['evento']?.toString().trim() ?? '';
    if (code.isEmpty || event.isEmpty) {
      return null;
    }

    return TrackingEventSummary(
      table: item['tabla']?.toString().trim() ?? '',
      service: item['servicio']?.toString().trim() ?? '',
      id: _toInt(item['id']),
      code: code,
      eventId: _toInt(item['evento_id']),
      event: event,
      detail: item['detalle']?.toString().trim() ?? '',
      userId: _toInt(item['user_id']),
      user: item['usuario']?.toString().trim() ?? '',
      createdAt: item['created_at']?.toString().trim() ?? '',
      photo: item['foto']?.toString().trim() ?? '',
    );
  }

  PackageCategory? _resolveCategory({
    required String rawCategory,
    required String fallbackCode,
  }) {
    final normalizedCategory = packageCategoryFromName(rawCategory);
    if (normalizedCategory != null) {
      return normalizedCategory;
    }

    final plan = PackageCodeClassifier.build(fallbackCode);
    if (!plan.searchAll && plan.targets.isNotEmpty) {
      return plan.targets.first;
    }
    return null;
  }

  int _toInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int? _toNullableInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) return const <String>[];
    return value
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> _getJsonMapWithCache({
    required String path,
    required String cacheKey,
  }) async {
    try {
      final payload = await _client.getJsonMap(path, authorize: true);
      unawaited(_storeCachedJsonMap(cacheKey, payload));
      return payload;
    } on ApiException catch (error) {
      final cachedPayload = await _readCachedJsonMap(cacheKey);
      if (cachedPayload != null) {
        return cachedPayload;
      }
      throw StateError(error.message);
    }
  }

  Future<void> _storeCachedJsonMap(
    String key,
    Map<String, dynamic> payload,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(payload));
      await prefs.setString(
        '$key$_cacheSavedAtSuffix',
        DateTime.now().toIso8601String(),
      );
    } catch (_) {
      // The live response is still usable even if local cache persistence fails.
    }
  }

  Future<Map<String, dynamic>?> _readCachedJsonMap(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.trim().isEmpty) {
        return null;
      }

      final savedAtRaw = prefs.getString('$key$_cacheSavedAtSuffix');
      final savedAt = DateTime.tryParse((savedAtRaw ?? '').trim());
      if (savedAt == null ||
          DateTime.now().difference(savedAt) > _diskCacheTtl) {
        await prefs.remove(key);
        await prefs.remove('$key$_cacheSavedAtSuffix');
        return null;
      }

      if (raw.length >= _cachedJsonIsolateDecodeThreshold) {
        return await compute(_decodeCachedJsonMap, raw);
      }
      return _decodeCachedJsonMap(raw);
    } catch (_) {
      return null;
    }
  }

  /// Removes all local cache entries used by this repository.
  /// Call this on logout to prevent stale or leaked data.
  static Future<void> clearLocalCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keysToRemove = prefs
          .getKeys()
          .where(
            (key) =>
                key.startsWith(_assignmentsCachePrefix) ||
                key.startsWith(_inventoryCachePrefix) ||
                key.startsWith(_legacyInventoryCachePrefix),
          )
          .toList(growable: false);
      for (final key in keysToRemove) {
        await prefs.remove(key);
      }
    } catch (_) {
      // Best-effort cleanup; failures are not critical.
    }
  }
}
