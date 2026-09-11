import 'package:flutter/material.dart';

import 'package:scan_agbc/funcionalidades/mantenimiento/dominio/modelos/mantenimiento_models.dart';
import 'package:scan_agbc/funcionalidades/mantenimiento/dominio/repositorios/mantenimiento_repository.dart';
import 'package:scan_agbc/nucleo/componentes/app_feedback_banner.dart';
import 'package:scan_agbc/nucleo/componentes/app_page_scaffold.dart';

class NuevoMantenimientoPage extends StatefulWidget {
  const NuevoMantenimientoPage({super.key, required this.repository});

  final MantenimientoRepository repository;

  @override
  State<NuevoMantenimientoPage> createState() => _NuevoMantenimientoPageState();
}

class _NuevoMantenimientoPageState extends State<NuevoMantenimientoPage> {
  final _formKey = GlobalKey<FormState>();
  late Future<MantenimientoOptions> _optionsFuture;
  int? _vehicleId;
  int? _typeId;
  DateTime? _scheduledAt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _optionsFuture = widget.repository.loadOptions();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final value = await showDatePicker(
      context: context,
      initialDate: _scheduledAt ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: 'Fecha programada',
    );
    if (value != null) setState(() => _scheduledAt = value);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _scheduledAt == null) {
      if (_scheduledAt == null) {
        showAppFeedbackBanner(
          context,
          'Selecciona la fecha programada.',
          tone: AppFeedbackTone.error,
        );
      }
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.repository.create(
        vehicleId: _vehicleId!,
        maintenanceTypeId: _typeId!,
        scheduledAt: _scheduledAt!,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      showAppFeedbackBanner(
        context,
        error.toString().replaceFirst('Bad state: ', ''),
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatDate(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

  @override
  Widget build(BuildContext context) => AppPageScaffold(
    title: 'Solicitar mantenimiento',
    appBar: AppBar(title: const Text('Solicitar mantenimiento')),
    bodyPadding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
    body: FutureBuilder<MantenimientoOptions>(
      future: _optionsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: FilledButton.icon(
              onPressed: () => setState(
                () => _optionsFuture = widget.repository.loadOptions(),
              ),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          );
        }

        final options = snapshot.data!;
        return SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Nueva solicitud',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Selecciona el vehículo y programa el mantenimiento.',
                ),
                const SizedBox(height: 22),
                DropdownButtonFormField<int>(
                  initialValue: _vehicleId,
                  decoration: const InputDecoration(
                    labelText: 'Vehículo',
                    prefixIcon: Icon(Icons.directions_car_rounded),
                    border: OutlineInputBorder(),
                  ),
                  items: options.vehicles
                      .where((item) => item.available)
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _vehicleId = value),
                  validator: (value) =>
                      value == null ? 'Selecciona un vehículo.' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: _typeId,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de mantenimiento',
                    prefixIcon: Icon(Icons.build_circle_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: options.types
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(
                            item.category.isEmpty
                                ? item.name
                                : '${item.name} · ${item.category}',
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _typeId = value),
                  validator: (value) => value == null
                      ? 'Selecciona el tipo de mantenimiento.'
                      : null,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _pickDate,
                  icon: const Icon(Icons.event_rounded),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    child: Text(
                      _scheduledAt == null
                          ? 'Seleccionar fecha programada'
                          : _formatDate(_scheduledAt!),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      _saving ? 'Enviando…' : 'Solicitar mantenimiento',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
