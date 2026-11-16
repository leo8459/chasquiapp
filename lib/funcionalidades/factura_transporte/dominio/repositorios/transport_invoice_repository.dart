import 'dart:typed_data';

abstract interface class TransportInvoiceRepository {
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
  });
}
