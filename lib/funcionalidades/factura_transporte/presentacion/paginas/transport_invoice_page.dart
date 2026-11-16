import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:scan_agbc/funcionalidades/factura_transporte/dominio/repositorios/transport_invoice_repository.dart';
import 'package:scan_agbc/nucleo/componentes/app_page_scaffold.dart';
import 'package:scan_agbc/nucleo/componentes/app_success_dialog.dart';
import 'package:scan_agbc/nucleo/tema/app_theme.dart';

class TransportInvoicePage extends StatefulWidget {
  const TransportInvoicePage({super.key, required this.repository});

  final TransportInvoiceRepository repository;

  @override
  State<TransportInvoicePage> createState() => _TransportInvoicePageState();
}

class _TransportInvoicePageState extends State<TransportInvoicePage> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _carrierController = TextEditingController();
  final _provinceController = TextEditingController();
  final _invoiceController = TextEditingController();
  final _amountController = TextEditingController();
  final _weightController = TextEditingController();
  final _picker = ImagePicker();

  String _transportType = 'terrestre';
  XFile? _invoicePhoto;
  bool _saving = false;

  @override
  void dispose() {
    _codeController.dispose();
    _carrierController.dispose();
    _provinceController.dispose();
    _invoiceController.dispose();
    _amountController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final photo = await _picker.pickImage(
        source: source,
        imageQuality: 86,
        maxWidth: 1800,
        maxHeight: 1800,
      );
      if (photo == null || !mounted) return;
      setState(() => _invoicePhoto = photo);
    } catch (_) {
      if (!mounted) return;
      _showMessage('No se pudo abrir la cámara o la galería.');
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final photo = _invoicePhoto;
    if (photo == null) {
      _showMessage('Adjunta una foto o PDF de la factura de transporte.');
      return;
    }

    final amount = _parseNumber(_amountController.text);
    final weight = _parseNumber(_weightController.text);
    if (amount == null || weight == null) return;

    setState(() => _saving = true);
    try {
      final Uint8List photoBytes = await photo.readAsBytes();
      await widget.repository.create(
        specialCode: _codeController.text,
        transportType: _transportType,
        carrier: _carrierController.text,
        province: _provinceController.text,
        invoiceNumber: _invoiceController.text,
        totalAmount: amount,
        weight: weight,
        invoicePhotoBytes: photoBytes,
        invoicePhotoFileName: photo.name,
        invoicePhotoContentType: photo.mimeType ?? 'image/jpeg',
      );

      if (!mounted) return;
      await showAppSuccessDialog(
        context,
        title: '¡Factura registrada!',
        message: 'La factura ya aparece en la vista de Bitácoras de BoliPost.',
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        _showMessage(error.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  double? _parseNumber(String raw) =>
      double.tryParse(raw.trim().replaceAll(',', '.'));

  String? _requiredText(String? value) =>
      value == null || value.trim().isEmpty ? 'Campo obligatorio.' : null;

  String? _validNumber(String? value, {required String label, double? max}) {
    final number = _parseNumber(value ?? '');
    if (number == null || number < 0) return 'Ingresa $label válido.';
    if (max != null && number > max) return '$label no puede superar $max.';
    return null;
  }

  @override
  Widget build(BuildContext context) => AppPageScaffold(
    title: 'Factura de transporte',
    bodyPadding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
    body: Form(
      key: _formKey,
      child: ListView(
        children: [
          _introCard(context),
          const SizedBox(height: 14),
          TextFormField(
            controller: _codeController,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Código especial',
              hintText: 'Ej. CN33-123456',
              prefixIcon: Icon(Icons.qr_code_2_rounded),
            ),
            validator: _requiredText,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _transportType,
            decoration: const InputDecoration(
              labelText: 'Tipo de transporte',
              prefixIcon: Icon(Icons.local_shipping_outlined),
            ),
            items: const [
              DropdownMenuItem(value: 'terrestre', child: Text('Terrestre')),
              DropdownMenuItem(value: 'aereo', child: Text('Aéreo (BOA)')),
            ],
            onChanged: _saving
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() => _transportType = value);
                  },
          ),
          if (_transportType == 'terrestre') ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _carrierController,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Transportadora',
                prefixIcon: Icon(Icons.business_outlined),
              ),
              validator: _requiredText,
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: _provinceController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Provincia (opcional)',
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _invoiceController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Número de factura',
              prefixIcon: Icon(Icons.receipt_long_outlined),
            ),
            validator: _requiredText,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Importe total (Bs)',
              prefixIcon: Icon(Icons.payments_outlined),
            ),
            validator: (value) => _validNumber(value, label: 'un importe'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _weightController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Peso del envío (kg)',
              prefixIcon: Icon(Icons.scale_outlined),
            ),
            validator: (value) =>
                _validNumber(value, label: 'un peso', max: 150),
          ),
          const SizedBox(height: 16),
          _photoCard(),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _submit,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload_outlined),
            label: Text(_saving ? 'Registrando…' : 'Registrar factura'),
          ),
        ],
      ),
    ),
  );

  Widget _introCard(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: AppTheme.buildSoftCardDecoration(
      backgroundColor: const Color(0xFFFFF1CF),
      borderRadius: BorderRadius.circular(14),
      borderColor: AppTheme.softBorder,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, color: AppTheme.blue),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Completa los datos del transporte. Al guardar, el registro aparecerá en la vista de Bitácoras de BoliPost.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.blue,
              height: 1.35,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _photoCard() => Container(
    padding: const EdgeInsets.all(14),
    decoration: AppTheme.buildSoftCardDecoration(
      backgroundColor: Colors.white,
      borderRadius: BorderRadius.circular(14),
      borderColor: AppTheme.softBorder,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Comprobante de factura',
          style: TextStyle(color: AppTheme.blue, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        const Text('Adjunta una foto legible de la factura.'),
        const SizedBox(height: 12),
        if (_invoicePhoto case final photo?) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              File(photo.path),
              width: double.infinity,
              height: 190,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 8),
          Text(photo.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _saving ? null : () => _pickPhoto(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Tomar foto'),
            ),
            OutlinedButton.icon(
              onPressed: _saving ? null : () => _pickPhoto(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Elegir imagen'),
            ),
          ],
        ),
      ],
    ),
  );
}
