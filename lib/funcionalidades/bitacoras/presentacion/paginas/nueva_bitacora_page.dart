import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import 'package:scan_agbc/funcionalidades/bitacoras/dominio/modelos/bitacora_options.dart';
import 'package:scan_agbc/funcionalidades/bitacoras/dominio/repositorios/bitacora_repository.dart';
import 'package:scan_agbc/nucleo/componentes/app_feedback_banner.dart';
import 'package:scan_agbc/nucleo/componentes/app_page_scaffold.dart';
import 'package:scan_agbc/nucleo/tema/app_theme.dart';

class NuevaBitacoraPage extends StatefulWidget {
  const NuevaBitacoraPage({super.key, required this.repository});

  final BitacoraRepository repository;

  @override
  State<NuevaBitacoraPage> createState() => _NuevaBitacoraPageState();
}

class _NuevaBitacoraPageState extends State<NuevaBitacoraPage> {
  final _formKey = GlobalKey<FormState>();
  final _startMileageController = TextEditingController();
  final _traveledMileageController = TextEditingController();
  final _startLocationController = TextEditingController();
  final _destinationLocationController = TextEditingController();
  final _imagePicker = ImagePicker();

  late Future<BitacoraOptions> _optionsFuture;
  DateTime _date = DateTime.now();
  int? _driverId;
  int? _vehicleId;
  LatLng? _startPosition;
  LatLng? _destinationPosition;
  Uint8List? _photoBytes;
  String _photoName = 'odometro.jpg';
  String _photoContentType = 'image/jpeg';
  bool _gettingStartLocation = false;
  bool _gettingDestinationLocation = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _optionsFuture = widget.repository.loadOptions();
  }

  @override
  void dispose() {
    _startMileageController.dispose();
    _traveledMileageController.dispose();
    _startLocationController.dispose();
    _destinationLocationController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (selected != null && mounted) setState(() => _date = selected);
  }

  Future<void> _captureLocation({required bool isStart}) async {
    setState(() {
      if (isStart) {
        _gettingStartLocation = true;
      } else {
        _gettingDestinationLocation = true;
      }
    });

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('Activa la ubicación GPS del teléfono.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError(
          permission == LocationPermission.deniedForever
              ? 'Habilita el permiso de ubicación desde Ajustes.'
              : 'Necesitamos permiso de ubicación para registrar la ruta.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (!mounted) return;
      setState(() {
        final selectedPosition = LatLng(position.latitude, position.longitude);
        if (isStart) {
          _startPosition = selectedPosition;
        } else {
          _destinationPosition = selectedPosition;
        }
      });
    } catch (error) {
      if (!mounted) return;
      showAppFeedbackBanner(
        context,
        _errorMessage(error),
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          if (isStart) {
            _gettingStartLocation = false;
          } else {
            _gettingDestinationLocation = false;
          }
        });
      }
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
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
  }

  Future<void> _selectLocationOnMap({required bool isStart}) async {
    final selected = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => _LocationMapPickerPage(
          title: isStart
              ? 'Seleccionar punto de inicio'
              : 'Seleccionar destino',
          initialPosition: isStart ? _startPosition : _destinationPosition,
        ),
      ),
    );
    if (selected == null || !mounted) return;

    setState(() {
      if (isStart) {
        _startPosition = selected;
      } else {
        _destinationPosition = selected;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startPosition == null || _destinationPosition == null) {
      showAppFeedbackBanner(
        context,
        'Captura la ubicación GPS del inicio y del destino.',
        tone: AppFeedbackTone.error,
      );
      return;
    }
    if (_photoBytes == null || _photoBytes!.isEmpty) {
      showAppFeedbackBanner(
        context,
        'Toma o selecciona una foto del odómetro.',
        tone: AppFeedbackTone.error,
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.repository.create(
        vehicleId: _vehicleId!,
        driverId: _driverId!,
        date: _date,
        startMileage: double.parse(_startMileageController.text.trim()),
        traveledMileage: double.parse(_traveledMileageController.text.trim()),
        startLocation: _startLocationController.text,
        destinationLocation: _destinationLocationController.text,
        startLatitude: _startPosition!.latitude,
        startLongitude: _startPosition!.longitude,
        destinationLatitude: _destinationPosition!.latitude,
        destinationLongitude: _destinationPosition!.longitude,
        odometerPhotoBytes: _photoBytes!,
        odometerPhotoFileName: _photoName,
        odometerPhotoContentType: _photoContentType,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
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
      title: 'Nueva bitácora',
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
                _optionsFuture = widget.repository.loadOptions();
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
                  'No hay conductores o vehículos disponibles para crear la bitácora.',
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
                _SectionCard(
                  title: 'Responsable y vehículo',
                  icon: Icons.badge_rounded,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: _driverId,
                      decoration: const InputDecoration(
                        labelText: 'Conductor',
                        prefixIcon: Icon(Icons.person_rounded),
                      ),
                      items: drivers
                          .map(
                            (driver) => DropdownMenuItem(
                              value: driver.id,
                              child: Text(driver.name),
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
                            (vehicle) => DropdownMenuItem(
                              value: vehicle.id,
                              child: Text(vehicle.label),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) => setState(() => _vehicleId = value),
                      validator: (value) =>
                          value == null ? 'Selecciona un vehículo.' : null,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _selectDate,
                      icon: const Icon(Icons.calendar_today_rounded),
                      label: Text('Fecha: ${_formatDate(_date)}'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _SectionCard(
                  title: 'Kilometraje',
                  icon: Icons.speed_rounded,
                  children: [
                    _NumberField(
                      controller: _startMileageController,
                      label: 'Kilometraje de salida',
                      validator: (value) {
                        final number = double.tryParse(value ?? '');
                        return number == null || number <= 0
                            ? 'Ingresa un kilometraje mayor a cero.'
                            : null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _NumberField(
                      controller: _traveledMileageController,
                      label: 'Kilómetros recorridos',
                      validator: (value) {
                        final number = double.tryParse(value ?? '');
                        return number == null || number < 0
                            ? 'Ingresa un valor válido.'
                            : null;
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _LocationCard(
                  title: 'Punto de inicio',
                  controller: _startLocationController,
                  position: _startPosition,
                  loading: _gettingStartLocation,
                  onCapture: () => _captureLocation(isStart: true),
                  onSelectOnMap: () => _selectLocationOnMap(isStart: true),
                ),
                const SizedBox(height: 14),
                _LocationCard(
                  title: 'Punto de destino',
                  controller: _destinationLocationController,
                  position: _destinationPosition,
                  loading: _gettingDestinationLocation,
                  onCapture: () => _captureLocation(isStart: false),
                  onSelectOnMap: () => _selectLocationOnMap(isStart: false),
                ),
                const SizedBox(height: 14),
                _SectionCard(
                  title: 'Foto del odómetro',
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
                            onPressed: () => _pickPhoto(ImageSource.camera),
                            icon: const Icon(Icons.photo_camera_rounded),
                            label: const Text('Cámara'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickPhoto(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library_rounded),
                            label: const Text('Galería'),
                          ),
                        ),
                      ],
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
                  label: Text(_saving ? 'Guardando...' : 'Crear bitácora'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _formatDate(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';

  static String _errorMessage(Object error) {
    final message = error.toString();
    return message.startsWith('Bad state: ')
        ? message.substring('Bad state: '.length)
        : message;
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
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

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.validator,
  });

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String> validator;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [
      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
    ],
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: const Icon(Icons.speed_rounded),
      suffixText: 'km',
    ),
    validator: validator,
  );
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.title,
    required this.controller,
    required this.position,
    required this.loading,
    required this.onCapture,
    required this.onSelectOnMap,
  });

  final String title;
  final TextEditingController controller;
  final LatLng? position;
  final bool loading;
  final VoidCallback onCapture;
  final VoidCallback onSelectOnMap;

  @override
  Widget build(BuildContext context) => _SectionCard(
    title: title,
    icon: Icons.location_on_rounded,
    children: [
      TextFormField(
        controller: controller,
        minLines: 2,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Dirección o descripción del lugar',
          alignLabelWithHint: true,
        ),
        validator: (value) => (value ?? '').trim().isEmpty
            ? 'Escribe la dirección o descripción.'
            : null,
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onSelectOnMap,
              icon: const Icon(Icons.map_rounded),
              label: Text(
                position == null ? 'Elegir en mapa' : 'Cambiar en mapa',
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: loading ? null : onCapture,
              icon: loading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location_rounded),
              label: const Text('Mi GPS'),
            ),
          ),
        ],
      ),
      if (position != null) ...[
        const SizedBox(height: 10),
        Container(
          height: 145,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: AppTheme.radiusMedium,
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: IgnorePointer(
            child: FlutterMap(
              options: MapOptions(initialCenter: position!, initialZoom: 16),
              children: [
                _buildTileLayer(),
                MarkerLayer(markers: [_buildLocationMarker(position!)]),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '${position!.latitude.toStringAsFixed(6)}, '
            '${position!.longitude.toStringAsFixed(6)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ],
  );
}

class _LocationMapPickerPage extends StatefulWidget {
  const _LocationMapPickerPage({
    required this.title,
    required this.initialPosition,
  });

  final String title;
  final LatLng? initialPosition;

  @override
  State<_LocationMapPickerPage> createState() => _LocationMapPickerPageState();
}

class _LocationMapPickerPageState extends State<_LocationMapPickerPage> {
  static const _defaultPosition = LatLng(-16.4897, -68.1193);
  late LatLng _selectedPosition;

  @override
  void initState() {
    super.initState();
    _selectedPosition = widget.initialPosition ?? _defaultPosition;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: _selectedPosition,
            initialZoom: widget.initialPosition == null ? 13 : 16,
            onTap: (_, point) => setState(() => _selectedPosition = point),
          ),
          children: [
            _buildTileLayer(),
            MarkerLayer(markers: [_buildLocationMarker(_selectedPosition)]),
            const RichAttributionWidget(
              attributions: [
                TextSourceAttribution('OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
        Positioned(
          top: 12,
          left: 16,
          right: 16,
          child: Material(
            elevation: 3,
            borderRadius: AppTheme.radiusMedium,
            color: Theme.of(context).colorScheme.surface,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Text(
                'Toca el mapa para colocar el marcador en el lugar exacto.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: SafeArea(
            top: false,
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(_selectedPosition),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Usar esta ubicación'),
            ),
          ),
        ),
      ],
    ),
  );
}

TileLayer _buildTileLayer() => TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  userAgentPackageName: 'bo.gob.correos.scan_agbc',
);

Marker _buildLocationMarker(LatLng point) => Marker(
  point: point,
  width: 52,
  height: 52,
  alignment: Alignment.topCenter,
  child: const Icon(Icons.location_pin, size: 48, color: AppTheme.errorRed),
);

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
