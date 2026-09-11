import 'package:scan_agbc/funcionalidades/mantenimiento/dominio/modelos/mantenimiento_models.dart';

abstract interface class MantenimientoRepository {
  Future<MantenimientoResult> findAll({int page = 1, int perPage = 20});

  Future<MantenimientoOptions> loadOptions();

  Future<void> create({
    required int vehicleId,
    required int maintenanceTypeId,
    required DateTime scheduledAt,
  });
}
