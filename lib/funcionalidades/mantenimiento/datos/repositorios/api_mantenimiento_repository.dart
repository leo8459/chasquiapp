import 'package:scan_agbc/funcionalidades/mantenimiento/dominio/modelos/mantenimiento_models.dart';
import 'package:scan_agbc/funcionalidades/mantenimiento/dominio/repositorios/mantenimiento_repository.dart';
import 'package:scan_agbc/nucleo/red/api_client.dart';

class ApiMantenimientoRepository implements MantenimientoRepository {
  const ApiMantenimientoRepository(this._client);

  final ApiClient _client;

  @override
  Future<MantenimientoResult> findAll({int page = 1, int perPage = 20}) async {
    try {
      final payload = await _client.getJsonMap(
        '/mobile/mantenimientos',
        authorize: true,
        queryParameters: {'page': '$page', 'per_page': '$perPage'},
      );
      final rawEntries = payload['data'];
      return MantenimientoResult(
        currentPage: _toInt(payload['current_page'], fallback: page),
        lastPage: _toInt(payload['last_page'], fallback: 1),
        perPage: _toInt(payload['per_page'], fallback: perPage),
        total: _toInt(payload['total']),
        entries: rawEntries is List
            ? rawEntries
                  .map(_mapEntry)
                  .whereType<MantenimientoEntry>()
                  .toList(growable: false)
            : const <MantenimientoEntry>[],
      );
    } on ApiException catch (error) {
      throw StateError(error.message);
    }
  }

  @override
  Future<MantenimientoOptions> loadOptions() async {
    try {
      final payload = await _client.getJsonMap(
        '/mobile/mantenimientos/opciones',
        authorize: true,
      );
      final vehicles = payload['vehicles'];
      final types = payload['maintenance_types'];
      return MantenimientoOptions(
        vehicles: vehicles is List
            ? vehicles
                  .map(_mapVehicle)
                  .whereType<MantenimientoVehicle>()
                  .toList(growable: false)
            : const <MantenimientoVehicle>[],
        types: types is List
            ? types
                  .map(_mapType)
                  .whereType<MantenimientoType>()
                  .toList(growable: false)
            : const <MantenimientoType>[],
      );
    } on ApiException catch (error) {
      throw StateError(error.message);
    }
  }

  @override
  Future<void> create({
    required int vehicleId,
    required int maintenanceTypeId,
    required DateTime scheduledAt,
  }) async {
    try {
      await _client.postJsonMap(
        '/mobile/mantenimientos',
        authorize: true,
        body: {
          'vehicle_id': vehicleId,
          'maintenance_type_id': maintenanceTypeId,
          'fecha_programada': _dateOnly(scheduledAt),
        },
      );
    } on ApiException catch (error) {
      throw StateError(error.message);
    }
  }

  MantenimientoEntry? _mapEntry(dynamic raw) {
    if (raw is! Map) return null;
    return MantenimientoEntry(
      id: _toInt(raw['id']),
      vehicleId: _toInt(raw['vehicle_id']),
      vehiclePlate: raw['vehicle_plate']?.toString().trim() ?? '',
      vehicleName: raw['vehicle_name']?.toString().trim() ?? '',
      maintenanceTypeId: _toInt(raw['maintenance_type_id']),
      maintenanceType: raw['maintenance_type']?.toString().trim() ?? '',
      scheduledAt: DateTime.tryParse(
        raw['scheduled_at']?.toString().trim() ?? '',
      ),
      status: raw['status']?.toString().trim() ?? '',
      description: raw['description']?.toString().trim() ?? '',
      createdAt: DateTime.tryParse(raw['created_at']?.toString().trim() ?? ''),
    );
  }

  MantenimientoVehicle? _mapVehicle(dynamic raw) {
    if (raw is! Map) return null;
    return MantenimientoVehicle(
      id: _toInt(raw['id']),
      plate: raw['plate']?.toString().trim() ?? '',
      name: raw['name']?.toString().trim() ?? '',
      available: raw['available'] != false,
    );
  }

  MantenimientoType? _mapType(dynamic raw) {
    if (raw is! Map) return null;
    return MantenimientoType(
      id: _toInt(raw['id']),
      name: raw['name']?.toString().trim() ?? '',
      category: raw['category']?.toString().trim() ?? '',
      description: raw['description']?.toString().trim() ?? '',
    );
  }

  int _toInt(dynamic value, {int fallback = 0}) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

  String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
