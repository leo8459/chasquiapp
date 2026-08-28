class ScanResult {
  const ScanResult({
    required this.barcodeText,
    required this.nombre,
    required this.telefono,
    required this.peso,
    required this.ciudad,
    required this.zona,
    required this.aduana,
    required this.ventanillaId,
    required this.ventanillaNombre,
    required this.tipoDocumento,
    required this.observaciones,
    required this.createdAt,
  });

  final String barcodeText;
  final String nombre;
  final String telefono;
  final double peso;
  final String ciudad;
  final String zona;
  final bool aduana;
  final int ventanillaId;
  final String ventanillaNombre;
  final String tipoDocumento;
  final String observaciones;
  final DateTime createdAt;
}
