class ScannedFichaData {
  const ScannedFichaData({
    required this.barcode,
    required this.nombre,
    required this.direccion,
    required this.telefono,
    required this.ocrRaw,
    required this.ocrTokens,
  });

  final String barcode;
  final String nombre;
  final String direccion;
  final String telefono;
  final String ocrRaw;
  final List<String> ocrTokens;
}
