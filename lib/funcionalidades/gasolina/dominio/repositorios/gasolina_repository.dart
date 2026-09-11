import 'dart:typed_data';

import 'package:scan_agbc/funcionalidades/gasolina/dominio/modelos/gasolina_result.dart';

abstract interface class GasolinaRepository {
  Future<GasolinaResult> findAll({int page = 1, int perPage = 20});

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
  });
}
