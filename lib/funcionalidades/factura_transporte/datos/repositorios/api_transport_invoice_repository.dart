import 'dart:typed_data';

import 'package:scan_agbc/funcionalidades/factura_transporte/dominio/repositorios/transport_invoice_repository.dart';
import 'package:scan_agbc/nucleo/red/api_client.dart';

class ApiTransportInvoiceRepository implements TransportInvoiceRepository {
  const ApiTransportInvoiceRepository(this._client);

  final ApiClient _client;

  @override
  Future<void> create({
    required String specialCode,
    required String transportType,
    required String carrier,
    required String province,
    required String invoiceNumber,
    required double totalAmount,
    required double weight,
    required Uint8List invoicePhotoBytes,
    required String invoicePhotoFileName,
    required String invoicePhotoContentType,
  }) async {
    try {
      await _client.postMultipartMap(
        '/mobile/facturas-transporte',
        authorize: true,
        fields: {
          'cod_especial': specialCode.trim().toUpperCase(),
          'tipo_transporte': transportType,
          'transportadora': carrier.trim().toUpperCase(),
          'provincia': province.trim().toUpperCase(),
          'factura': invoiceNumber.trim(),
          'precio_total': '$totalAmount',
          'peso': '$weight',
        },
        fileField: 'imagen_factura',
        fileBytes: invoicePhotoBytes,
        fileName: invoicePhotoFileName,
        contentType: invoicePhotoContentType,
      );
    } on ApiException catch (error) {
      throw StateError(error.message);
    }
  }
}
