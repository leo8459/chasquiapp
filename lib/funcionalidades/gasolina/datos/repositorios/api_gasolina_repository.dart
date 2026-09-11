import 'dart:typed_data';

import 'package:scan_agbc/funcionalidades/gasolina/dominio/modelos/gasolina_result.dart';
import 'package:scan_agbc/funcionalidades/gasolina/dominio/repositorios/gasolina_repository.dart';
import 'package:scan_agbc/nucleo/red/api_client.dart';

class ApiGasolinaRepository implements GasolinaRepository {
  const ApiGasolinaRepository(this._client);

  final ApiClient _client;

  @override
  Future<GasolinaResult> findAll({int page = 1, int perPage = 20}) async {
    try {
      final payload = await _client.getJsonMap(
        '/mobile/gasolinas',
        authorize: true,
        queryParameters: {'page': '$page', 'per_page': '$perPage'},
      );
      final rawEntries = payload['data'];

      return GasolinaResult(
        currentPage: _toInt(payload['current_page'], fallback: page),
        lastPage: _toInt(payload['last_page'], fallback: 1),
        perPage: _toInt(payload['per_page'], fallback: perPage),
        total: _toInt(payload['total']),
        entries: rawEntries is List
            ? rawEntries
                  .map(_mapEntry)
                  .whereType<GasolinaEntry>()
                  .toList(growable: false)
            : const <GasolinaEntry>[],
      );
    } on ApiException catch (error) {
      throw StateError(error.message);
    }
  }

  @override
  Future<void> create({
    required int vehicleId,
    required int driverId,
    required String invoiceNumber,
    required String customerName,
    required DateTime issuedAt,
    required double liters,
    required double unitPrice,
    required Uint8List invoicePhotoBytes,
    required String invoicePhotoFileName,
    required String invoicePhotoContentType,
  }) async {
    final dateText = issuedAt.toIso8601String();

    try {
      await _client.postMultipartMap(
        '/mobile/gasolinas',
        authorize: true,
        fields: {
          'vehicle_id': '$vehicleId',
          'driver_id': '$driverId',
          'numero_factura': invoiceNumber.trim(),
          'nombre_cliente': customerName.trim(),
          'fecha_emision': dateText,
          'cantidad': '$liters',
          'precio_unitario': '$unitPrice',
        },
        fileField: 'invoice_photo',
        fileBytes: invoicePhotoBytes,
        fileName: invoicePhotoFileName,
        contentType: invoicePhotoContentType,
      );
    } on ApiException catch (error) {
      throw StateError(error.message);
    }
  }

  GasolinaEntry? _mapEntry(dynamic raw) {
    if (raw is! Map) return null;

    return GasolinaEntry(
      id: _toInt(raw['id']),
      stationName: raw['station_name']?.toString().trim() ?? '',
      totalAmount: _toDouble(raw['total_amount']),
      dateTime: DateTime.tryParse(raw['date_time']?.toString().trim() ?? ''),
      invoiceNumber: raw['invoice_number']?.toString().trim() ?? '',
      customerName: raw['customer_name']?.toString().trim() ?? '',
      vehiclePlate: raw['vehicle_plate']?.toString().trim() ?? '',
      driverName: raw['driver_name']?.toString().trim() ?? '',
      vehicleId: _toInt(raw['vehicle_id']),
      driverId: _toInt(raw['driver_id']),
      liters: _toDouble(raw['liters']),
      unitPrice: _toDouble(raw['unit_price']),
      status: raw['estado']?.toString().trim() ?? '',
    );
  }

  int _toInt(dynamic value, {int fallback = 0}) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

  double? _toDouble(dynamic value) => value == null
      ? null
      : (value is num ? value.toDouble() : double.tryParse('$value'));
}
