import 'dart:typed_data';

import 'package:scan_agbc/funcionalidades/bitacoras/dominio/modelos/bitacora_result.dart';
import 'package:scan_agbc/funcionalidades/bitacoras/dominio/modelos/bitacora_options.dart';

abstract interface class BitacoraRepository {
  Future<BitacoraResult> findAll({int page = 1, int perPage = 20});

  Future<BitacoraOptions> loadOptions();

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
  });
}
