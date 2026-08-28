import 'package:scan_agbc/funcionalidades/clasificacion/dominio/modelos/scan_result.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/dominio/modelos/ventanilla_option.dart';

abstract class ScanRepository {
  Future<void> saveScan(ScanResult result);
  Future<List<VentanillaOption>> getVentanillas();
}
