import 'package:flutter/material.dart';

import 'package:scan_agbc/funcionalidades/mantenimiento/dominio/modelos/mantenimiento_models.dart';
import 'package:scan_agbc/funcionalidades/mantenimiento/dominio/repositorios/mantenimiento_repository.dart';
import 'package:scan_agbc/funcionalidades/mantenimiento/presentacion/paginas/nuevo_mantenimiento_page.dart';
import 'package:scan_agbc/nucleo/componentes/app_page_scaffold.dart';
import 'package:scan_agbc/nucleo/componentes/app_success_dialog.dart';
import 'package:scan_agbc/nucleo/tema/app_theme.dart';
import 'package:scan_agbc/nucleo/utilidades/bolivia_date_time_formatter.dart';

class MantenimientosPage extends StatefulWidget {
  const MantenimientosPage({super.key, required this.repository});

  final MantenimientoRepository repository;

  @override
  State<MantenimientosPage> createState() => _MantenimientosPageState();
}

class _MantenimientosPageState extends State<MantenimientosPage> {
  static const _perPage = 20;
  late Future<MantenimientoResult> _future;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<MantenimientoResult> _load() =>
      widget.repository.findAll(page: _page, perPage: _perPage);

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _future = future);
    await future;
  }

  void _goTo(int page) => setState(() {
    _page = page;
    _future = _load();
  });

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NuevoMantenimientoPage(repository: widget.repository),
      ),
    );
    if (created != true || !mounted) return;
    setState(() {
      _page = 1;
      _future = _load();
    });
    await showAppSuccessDialog(
      context,
      title: '¡Solicitud exitosa!',
      message: 'La solicitud de mantenimiento fue creada correctamente.',
    );
  }

  @override
  Widget build(BuildContext context) => AppPageScaffold(
    title: 'Solicitar mantenimiento',
    appBar: AppBar(
      title: const Text(
        'Mantenimientos',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      actions: [
        IconButton(
          tooltip: 'Nueva solicitud',
          onPressed: _openCreate,
          icon: const Icon(Icons.add_circle_outline_rounded),
        ),
        IconButton(
          tooltip: 'Actualizar',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _openCreate,
      icon: const Icon(Icons.add_rounded),
      label: const Text('Solicitar'),
    ),
    bodyPadding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
    body: FutureBuilder<MantenimientoResult>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErrorState(onRetry: _refresh);
        }
        final result = snapshot.data!;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _Summary(result: result),
              const SizedBox(height: 12),
              if (result.entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 100),
                  child: Column(
                    children: [
                      Icon(
                        Icons.build_circle_outlined,
                        size: 64,
                        color: AppTheme.blue,
                      ),
                      SizedBox(height: 14),
                      Text(
                        'No hay solicitudes de mantenimiento.',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                )
              else
                ...result.entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _MantenimientoCard(entry: entry),
                  ),
                ),
              if (result.lastPage > 1)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    OutlinedButton(
                      onPressed: result.currentPage > 1
                          ? () => _goTo(result.currentPage - 1)
                          : null,
                      child: const Text('Anterior'),
                    ),
                    Text('${result.currentPage} / ${result.lastPage}'),
                    OutlinedButton(
                      onPressed: result.currentPage < result.lastPage
                          ? () => _goTo(result.currentPage + 1)
                          : null,
                      child: const Text('Siguiente'),
                    ),
                  ],
                ),
              const SizedBox(height: 78),
            ],
          ),
        );
      },
    ),
  );
}

class _Summary extends StatelessWidget {
  const _Summary({required this.result});
  final MantenimientoResult result;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: AppTheme.buildPanelDecoration(),
    child: Row(
      children: [
        const CircleAvatar(
          backgroundColor: AppTheme.blue,
          child: Icon(Icons.build_rounded, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${result.total} solicitudes',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text('Página ${result.currentPage} de ${result.lastPage}'),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MantenimientoCard extends StatelessWidget {
  const _MantenimientoCard({required this.entry});
  final MantenimientoEntry entry;

  Future<void> _showDetails(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        entry.maintenanceType.isEmpty
            ? 'Mantenimiento #${entry.id}'
            : entry.maintenanceType,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Detail(Icons.tag_rounded, 'Solicitud #${entry.id}'),
            _Detail(Icons.directions_car_rounded, entry.vehiclePlate),
            _Detail(Icons.info_outline_rounded, entry.vehicleName),
            _Detail(
              Icons.event_rounded,
              BoliviaDateTimeFormatter.format(entry.scheduledAt),
            ),
            _Detail(Icons.flag_rounded, entry.status),
            if (entry.description.isNotEmpty)
              _Detail(Icons.notes_rounded, entry.description),
            if (entry.createdAt != null)
              _Detail(
                Icons.schedule_rounded,
                'Creado: ${BoliviaDateTimeFormatter.format(entry.createdAt)}',
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: AppTheme.buildSoftCardDecoration(
      backgroundColor: AppTheme.yellowSurface,
      borderRadius: AppTheme.radiusMedium,
      borderColor: AppTheme.softBorder,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                entry.maintenanceType.isEmpty
                    ? 'Mantenimiento #${entry.id}'
                    : entry.maintenanceType,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (entry.status.isNotEmpty)
              Chip(
                label: Text(entry.status),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: 8),
        _Detail(Icons.directions_car_rounded, entry.vehiclePlate),
        _Detail(
          Icons.event_rounded,
          BoliviaDateTimeFormatter.format(entry.scheduledAt),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: () => _showDetails(context),
            icon: const Icon(Icons.visibility_rounded),
            label: const Text('Ver'),
          ),
        ),
      ],
    ),
  );
}

class _Detail extends StatelessWidget {
  const _Detail(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppTheme.blue),
        const SizedBox(width: 8),
        Expanded(child: Text(text.isEmpty ? '—' : text)),
      ],
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_rounded, size: 60, color: AppTheme.errorRed),
        const SizedBox(height: 14),
        const Text('No pudimos cargar los mantenimientos.'),
        const SizedBox(height: 14),
        FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
      ],
    ),
  );
}
