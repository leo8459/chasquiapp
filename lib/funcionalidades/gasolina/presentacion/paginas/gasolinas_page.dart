import 'package:flutter/material.dart';

import 'package:scan_agbc/funcionalidades/bitacoras/dominio/repositorios/bitacora_repository.dart';
import 'package:scan_agbc/funcionalidades/gasolina/dominio/modelos/gasolina_result.dart';
import 'package:scan_agbc/funcionalidades/gasolina/dominio/repositorios/gasolina_repository.dart';
import 'package:scan_agbc/funcionalidades/gasolina/presentacion/paginas/nueva_gasolina_page.dart';
import 'package:scan_agbc/nucleo/componentes/app_feedback_banner.dart';
import 'package:scan_agbc/nucleo/componentes/app_page_scaffold.dart';
import 'package:scan_agbc/nucleo/tema/app_theme.dart';
import 'package:scan_agbc/nucleo/utilidades/bolivia_date_time_formatter.dart';

class GasolinasPage extends StatefulWidget {
  const GasolinasPage({
    super.key,
    required this.repository,
    required this.bitacoraRepository,
  });

  final GasolinaRepository repository;
  final BitacoraRepository bitacoraRepository;

  @override
  State<GasolinasPage> createState() => _GasolinasPageState();
}

class _GasolinasPageState extends State<GasolinasPage> {
  static const _perPage = 20;
  late Future<GasolinaResult> _future;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<GasolinaResult> _load() =>
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
        builder: (_) => NuevaGasolinaPage(
          repository: widget.repository,
          bitacoraRepository: widget.bitacoraRepository,
        ),
      ),
    );
    if (created != true || !mounted) return;
    _page = 1;
    await _refresh();
    if (!mounted) return;
    showAppFeedbackBanner(
      context,
      'Registro de gasolina creado correctamente.',
      tone: AppFeedbackTone.success,
    );
  }

  @override
  Widget build(BuildContext context) => AppPageScaffold(
    title: 'Gasolina',
    appBar: AppBar(
      title: const Text(
        'Gasolina',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      actions: [
        IconButton(
          tooltip: 'Nuevo registro',
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
      label: const Text('Registrar gasolina'),
    ),
    bodyPadding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
    body: FutureBuilder<GasolinaResult>(
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
                  padding: EdgeInsets.only(top: 110),
                  child: Column(
                    children: [
                      Icon(
                        Icons.local_gas_station_outlined,
                        size: 64,
                        color: AppTheme.blue,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'No hay registros de gasolina.',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                )
              else
                ...result.entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _GasolinaCard(entry: entry),
                  ),
                ),
              if (result.lastPage > 1)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    OutlinedButton.icon(
                      onPressed: result.currentPage > 1
                          ? () => _goTo(result.currentPage - 1)
                          : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                      label: const Text('Anterior'),
                    ),
                    Text('${result.currentPage} / ${result.lastPage}'),
                    OutlinedButton.icon(
                      onPressed: result.currentPage < result.lastPage
                          ? () => _goTo(result.currentPage + 1)
                          : null,
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(Icons.chevron_right_rounded),
                      label: const Text('Siguiente'),
                    ),
                  ],
                ),
              const SizedBox(height: 76),
            ],
          ),
        );
      },
    ),
  );
}

class _Summary extends StatelessWidget {
  const _Summary({required this.result});
  final GasolinaResult result;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: AppTheme.buildPanelDecoration(),
    child: Row(
      children: [
        const CircleAvatar(
          backgroundColor: AppTheme.blue,
          child: Icon(Icons.local_gas_station_rounded, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${result.total} registros',
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

class _GasolinaCard extends StatelessWidget {
  const _GasolinaCard({required this.entry});
  final GasolinaEntry entry;

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
                entry.stationName.isEmpty
                    ? 'Carga de combustible'
                    : entry.stationName,
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
        const SizedBox(height: 10),
        _Detail(
          Icons.calendar_today_rounded,
          BoliviaDateTimeFormatter.format(entry.dateTime),
        ),
        _Detail(Icons.receipt_rounded, 'Factura ${entry.invoiceNumber}'),
        _Detail(Icons.person_rounded, entry.driverName),
        _Detail(Icons.directions_car_rounded, entry.vehiclePlate),
        _Detail(
          Icons.water_drop_rounded,
          '${entry.liters?.toStringAsFixed(2) ?? '—'} L · ${entry.unitPrice?.toStringAsFixed(2) ?? '—'} Bs/L',
        ),
        const Divider(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Monto total'),
            Text(
              '${entry.totalAmount?.toStringAsFixed(2) ?? '—'} Bs',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: AppTheme.blue),
            ),
          ],
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
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
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
        const Text('No pudimos cargar los registros de gasolina.'),
        const SizedBox(height: 14),
        FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
      ],
    ),
  );
}
