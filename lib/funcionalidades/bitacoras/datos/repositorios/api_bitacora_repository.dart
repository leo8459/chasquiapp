import 'dart:typed_data';

import 'package:scan_agbc/funcionalidades/bitacoras/dominio/modelos/bitacora_result.dart';
import 'package:scan_agbc/funcionalidades/bitacoras/dominio/modelos/bitacora_options.dart';
import 'package:scan_agbc/funcionalidades/bitacoras/dominio/repositorios/bitacora_repository.dart';
import 'package:scan_agbc/nucleo/red/api_client.dart';

class ApiBitacoraRepository implements BitacoraRepository {
  const ApiBitacoraRepository(this._client);

  final ApiClient _client;

  @override
  Future<BitacoraOptions> loadOptions() async {
    try {
      final payloads = await Future.wait([
        _client.getJsonMap('/mobile/bitacoras/conductores', authorize: true),
        _client.getJsonMap('/mobile/bitacoras/vehiculos', authorize: true),
      ]);

      final rawDrivers = payloads[0]['data'];
      final rawVehicles = payloads[1]['data'];
      final drivers = rawDrivers is List
          ? rawDrivers
                .whereType<Map>()
                .map(
                  (item) => BitacoraDriverOption(
                    id: _toInt(item['id']),
                    name: item['nombre']?.toString().trim() ?? '',
                  ),
                )
                .where((item) => item.id > 0 && item.name.isNotEmpty)
                .toList()
          : <BitacoraDriverOption>[];
      final vehicles = rawVehicles is List
          ? rawVehicles
                .whereType<Map>()
                .map((item) {
                  final description = [
                    item['placa']?.toString().trim() ?? '',
                    item['marca']?.toString().trim() ?? '',
                    item['modelo']?.toString().trim() ?? '',
                  ].where((value) => value.isNotEmpty).join(' · ');
                  return BitacoraVehicleOption(
                    id: _toInt(item['id']),
                    label: description,
                  );
                })
                .where((item) => item.id > 0 && item.label.isNotEmpty)
                .toList()
          : <BitacoraVehicleOption>[];

      drivers.sort((a, b) => a.name.compareTo(b.name));
      vehicles.sort((a, b) => a.label.compareTo(b.label));
      return BitacoraOptions(drivers: drivers, vehicles: vehicles);
    } on ApiException catch (error) {
      throw StateError(error.message);
    }
  }

  @override
  Future<BitacoraResult> findAll({int page = 1, int perPage = 20}) async {
    try {
      final payload = await _client.getJsonMap(
        '/mobile/bitacoras',
        authorize: true,
        queryParameters: {'page': '$page', 'per_page': '$perPage'},
      );
      final rawEntries = payload['data'];

      return BitacoraResult(
        currentPage: _toInt(payload['current_page'], fallback: page),
        lastPage: _toInt(payload['last_page'], fallback: 1),
        perPage: _toInt(payload['per_page'], fallback: perPage),
        total: _toInt(payload['total']),
        entries: rawEntries is List
            ? rawEntries
                  .map(_mapEntry)
                  .whereType<BitacoraEntry>()
                  .toList(growable: false)
            : const <BitacoraEntry>[],
      );
    } on ApiException catch (error) {
      throw StateError(error.message);
    }
  }

  BitacoraEntry? _mapEntry(dynamic raw) {
    if (raw is! Map) return null;
    final driver = raw['driver'] is Map ? raw['driver'] as Map : const {};
    final vehicle = raw['vehicle'] is Map ? raw['vehicle'] as Map : const {};

    return BitacoraEntry(
      id: _toInt(raw['id']),
      date: DateTime.tryParse(raw['fecha']?.toString().trim() ?? ''),
      startMileage: _toDouble(raw['kilometraje_salida']),
      arrivalMileage: _toDouble(raw['kilometraje_llegada']),
      traveledMileage: _toDouble(raw['kilometraje_recorrido']),
      startLocation: raw['recorrido_inicio']?.toString().trim() ?? '',
      destinationLocation: raw['recorrido_destino']?.toString().trim() ?? '',
      fueled: raw['abastecimiento_combustible'] == true,
      active: raw['activo'] == true,
      packageCount: _toNullableInt(raw['cantidad_paquetes']),
      sessionReference: raw['session_reference']?.toString().trim() ?? '',
      driverId: _toInt(driver['id']),
      driverName: driver['nombre']?.toString().trim() ?? '',
      driverPhone: driver['telefono']?.toString().trim() ?? '',
      driverEmail: driver['email']?.toString().trim() ?? '',
      vehiclePlate: vehicle['placa']?.toString().trim() ?? '',
      vehicleId: _toInt(vehicle['id']),
      vehicleBrand: vehicle['marca']?.toString().trim() ?? '',
      vehicleModel: vehicle['modelo']?.toString().trim() ?? '',
      vehicleColor: vehicle['color']?.toString().trim() ?? '',
      vehicleYear: _toNullableInt(vehicle['anio']),
    );
  }

  @override
  Future<void> create({
    required int vehicleId,
    required int driverId,
    required DateTime date,
    required double startMileage,
    required double traveledMileage,
    required String startLocation,
    required String destinationLocation,
    required double startLatitude,
    required double startLongitude,
    required double destinationLatitude,
    required double destinationLongitude,
    required Uint8List odometerPhotoBytes,
    required String odometerPhotoFileName,
    required String odometerPhotoContentType,
  }) async {
    final dateText =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';

    try {
      await _client.postMultipartMap(
        '/mobile/bitacoras',
        authorize: true,
        fields: {
          'vehicles_id': '$vehicleId',
          'drivers_id': '$driverId',
          'fecha': dateText,
          'kilometraje_salida': '$startMileage',
          'kilometraje_recorrido': '$traveledMileage',
          'recorrido_inicio': startLocation.trim(),
          'recorrido_destino': destinationLocation.trim(),
          'latitud_inicio': '$startLatitude',
          'logitud_inicio': '$startLongitude',
          'latitud_destino': '$destinationLatitude',
          'logitud_destino': '$destinationLongitude',
        },
        fileField: 'odometro_photo',
        fileBytes: odometerPhotoBytes,
        fileName: odometerPhotoFileName,
        contentType: odometerPhotoContentType,
      );
    } on ApiException catch (error) {
      throw StateError(error.message);
    }
  }

  int _toInt(dynamic value, {int fallback = 0}) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

  int? _toNullableInt(dynamic value) => value == null
      ? null
      : (value is num ? value.toInt() : int.tryParse('$value'));

  double? _toDouble(dynamic value) => value == null
      ? null
      : (value is num ? value.toDouble() : double.tryParse('$value'));
}
