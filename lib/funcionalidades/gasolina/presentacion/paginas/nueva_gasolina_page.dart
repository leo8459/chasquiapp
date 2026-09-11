import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:scan_agbc/funcionalidades/bitacoras/dominio/modelos/bitacora_options.dart';
import 'package:scan_agbc/funcionalidades/bitacoras/dominio/repositorios/bitacora_repository.dart';
import 'package:scan_agbc/funcionalidades/gasolina/dominio/repositorios/gasolina_repository.dart';
import 'package:scan_agbc/nucleo/componentes/app_feedback_banner.dart';
import 'package:scan_agbc/nucleo/componentes/app_page_scaffold.dart';
import 'package:scan_agbc/nucleo/tema/app_theme.dart';

class NuevaGasolinaPage extends StatefulWidget {
  const NuevaGasolinaPage({
    super.key,
    required this.repository,
    required this.bitacoraRepository,
  });

  final GasolinaRepository repository;
  final BitacoraRepository bitacoraRepository;

  @override
  State<NuevaGasolinaPage> createState() => _NuevaGasolinaPageState();
}

class _NuevaGasolinaPageState extends State<NuevaGasolinaPage> {
  final _formKey = GlobalKey<FormState>();
  final _invoiceController = TextEditingController();
  final _customerController = TextEditingController(
    text: 'AGENCIA BOLIVIANA DE CORREOS',
  );
  final _litersController = TextEditingController();
  final _unitPriceController = TextEditingController();
  final _imagePicker = ImagePicker();

  late Future<BitacoraOptions> _optionsFuture;
  DateTime _issuedAt = DateTime.now();
  int? _vehicleId;
  int? _driverId;
  Uint8List? _photoBytes;
  String _photoName = 'factura.jpg';
  String _photoContentType = 'image/jpeg';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _optionsFuture = widget.bitacoraRepository.loadOptions();
  }

  @override
  void dispose() {
    _invoiceController.dispose();
    _customerController.dispose();
    _litersController.dispose();
    _unitPriceController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _issuedAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (value != null && mounted) setState(() => _issuedAt = value);
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 1920,
      );
      if (image == null) return;

      final bytes = await image.readAsBytes();
      if (!mounted) return;
      final lowerName = image.name.toLowerCase();
      setState(() {
        _photoBytes = bytes;
        _photoName = image.name;
        _photoContentType = lowerName.endsWith('.png')
            ? 'image/png'
            : 'image/jpeg';
      });
    } catch (error) {
      if (!mounted) return;
      showAppFeedbackBanner(
        context,
        'No pudimos leer la fotografía. Intenta nuevamente.',
        tone: AppFeedbackTone.error,
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_photoBytes == null || _photoBytes!.isEmpty) {
      showAppFeedbackBanner(
        context,
        'Toma o selecciona una fotografía de la factura.',
        tone: AppFeedbackTone.error,
      );
      return;
    }
    setState(() => _saving = true);

    try {
      await widget.repository.create(
        vehicleId: _vehicleId!,
        driverId: _driverId!,
        invoiceNumber: _invoiceController.text,
        customerName: _customerController.text,
        issuedAt: _issuedAt,
        liters: _number(_litersController.text)!,
        unitPrice: _number(_unitPriceController.text)!,
        invoicePhotoBytes: _photoBytes!,
        invoicePhotoFileName: _photoName,
        invoicePhotoContentType: _photoContentType,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      showAppFeedbackBanner(
        context,
        _errorMessage(error),
        tone: AppFeedbackTone.error,
        duration: const Duration(seconds: 5),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: 'Nuevo registro de gasolina',
      resizeToAvoidBottomInset: true,
      body: FutureBuilder<BitacoraOptions>(
        future: _optionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _OptionsError(
              onRetry: () => setState(() {
                _optionsFuture = widget.bitacoraRepository.loadOptions();
              }),
            );
          }

          final drivers = snapshot.data!.drivers;
          final vehicles = snapshot.data!.vehicles;
          if (drivers.isEmpty || vehicles.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No hay conductores o vehículos disponibles.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
              children: [
                _FormCard(
                  title: 'Responsable y vehículo',
                  icon: Icons.local_gas_station_rounded,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: _driverId,
                      decoration: const InputDecoration(
                        labelText: 'Conductor',
                        prefixIcon: Icon(Icons.person_rounded),
                      ),
                      items: drivers
                          .map(
                            (item) => DropdownMenuItem(
                              value: item.id,
                              child: Text(item.name),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) => setState(() => _driverId = value),
                      validator: (value) =>
                          value == null ? 'Selecciona un conductor.' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: _vehicleId,
                      decoration: const InputDecoration(
                        labelText: 'Vehículo',
                        prefixIcon: Icon(Icons.directions_car_rounded),
                      ),
                      items: vehicles
                          .map(
                            (item) => DropdownMenuItem(
                              value: item.id,
                              child: Text(item.label),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) => setState(() => _vehicleId = value),
                      validator: (value) =>
                          value == null ? 'Selecciona un vehículo.' : null,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _FormCard(
                  title: 'Datos de la factura',
                  icon: Icons.receipt_long_rounded,
                  children: [
                    TextFormField(
                      controller: _invoiceController,
                      decoration: const InputDecoration(
                        labelText: 'Número de factura',
                        prefixIcon: Icon(Icons.numbers_rounded),
                      ),
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _customerController,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del cliente',
                        prefixIcon: Icon(Icons.business_rounded),
                      ),
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _selectDate,
                      icon: const Icon(Icons.calendar_today_rounded),
                      label: Text('Fecha de emisión: ${_date(_issuedAt)}'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _FormCard(
                  title: 'Carga de combustible',
                  icon: Icons.ev_station_rounded,
                  children: [
                    _DecimalField(
                      controller: _litersController,
                      label: 'Cantidad de litros',
                      suffix: 'L',
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    _DecimalField(
                      controller: _unitPriceController,
                      label: 'Precio por litro',
                      suffix: 'Bs',
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total estimado'),
                        Text(
                          '${_total.toStringAsFixed(2)} Bs',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: AppTheme.blue),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _FormCard(
                  title: 'Fotografía de la factura',
                  icon: Icons.photo_camera_rounded,
                  children: [
                    if (_photoBytes != null) ...[
                      ClipRRect(
                        borderRadius: AppTheme.radiusMedium,
                        child: Image.memory(
                          _photoBytes!,
                          height: 190,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _saving
                                ? null
                                : () => _pickPhoto(ImageSource.camera),
                            icon: const Icon(Icons.photo_camera_rounded),
                            label: const Text('Cámara'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _saving
                                ? null
                                : () => _pickPhoto(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library_rounded),
                            label: const Text('Galería'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'La fotografía es obligatoria y se guardará como respaldo de la carga.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 19,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(_saving ? 'Guardando...' : 'Crear registro'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  double get _total =>
      (_number(_litersController.text) ?? 0) *
      (_number(_unitPriceController.text) ?? 0);

  static double? _number(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.'));

  static String? _required(String? value) =>
      (value ?? '').trim().isEmpty ? 'Este campo es obligatorio.' : null;

  static String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';

  static String _errorMessage(Object error) {
    final message = error.toString();
    return message.startsWith('Bad state: ')
        ? message.substring('Bad state: '.length)
        : message;
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: AppTheme.buildPanelDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppTheme.blue),
            const SizedBox(width: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 14),
        ...children,
      ],
    ),
  );
}

class _DecimalField extends StatelessWidget {
  const _DecimalField({
    required this.controller,
    required this.label,
    required this.suffix,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
    decoration: InputDecoration(labelText: label, suffixText: suffix),
    onChanged: onChanged,
    validator: (value) {
      final number = _NuevaGasolinaPageState._number(value ?? '');
      return number == null || number <= 0
          ? 'Ingresa un valor mayor a cero.'
          : null;
    },
  );
}

class _OptionsError extends StatelessWidget {
  const _OptionsError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 56,
            color: AppTheme.errorRed,
          ),
          const SizedBox(height: 14),
          const Text('No pudimos cargar conductores y vehículos.'),
          const SizedBox(height: 14),
          FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    ),
  );
}
