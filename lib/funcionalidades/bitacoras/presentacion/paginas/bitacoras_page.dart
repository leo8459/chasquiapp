import 'package:flutter/material.dart';

import 'package:scan_agbc/funcionalidades/bitacoras/dominio/modelos/bitacora_result.dart';
import 'package:scan_agbc/funcionalidades/bitacoras/dominio/repositorios/bitacora_repository.dart';
import 'package:scan_agbc/funcionalidades/bitacoras/presentacion/paginas/nueva_bitacora_page.dart';
import 'package:scan_agbc/nucleo/componentes/app_page_scaffold.dart';
import 'package:scan_agbc/nucleo/componentes/app_success_dialog.dart';
import 'package:scan_agbc/nucleo/tema/app_theme.dart';
import 'package:scan_agbc/nucleo/utilidades/bolivia_date_time_formatter.dart';

class BitacorasPage extends StatefulWidget {
  const BitacorasPage({super.key, required this.repository});

  final BitacoraRepository repository;

  @override
  State<BitacorasPage> createState() => _BitacorasPageState();
}

class _BitacorasPageState extends State<BitacorasPage> {
  static const int _perPage = 20;
  late Future<BitacoraResult> _resultFuture;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _resultFuture = _load();
  }

  Future<BitacoraResult> _load() =>
      widget.repository.findAll(page: _page, perPage: _perPage);

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _resultFuture = future);
    await future;
  }

  void _goToPage(int page) {
    setState(() {
      _page = page;
      _resultFuture = _load();
    });
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NuevaBitacoraPage(repository: widget.repository),
      ),
    );
    if (created != true || !mounted) return;
    setState(() {
      _page = 1;
      _resultFuture = _load();
    });
    await showAppSuccessDialog(
      context,
      title: '¡Registro exitoso!',
      message: 'La bitácora fue creada correctamente.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: 'Bitácoras',
      appBar: AppBar(
        title: const Text(
          'Bitácoras',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Nueva bitácora',
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
        label: const Text('Nueva bitácora'),
      ),
      bodyPadding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      body: FutureBuilder<BitacoraResult>(
        future: _resultFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(onRetry: _refresh);
          }

          final result = snapshot.data!;
          if (result.entries.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 140),
                  Icon(
                    Icons.menu_book_outlined,
                    size: 64,
                    color: AppTheme.blue,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No hay bitácoras registradas.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _SummaryHeader(result: result),
                const SizedBox(height: 12),
                ...result.entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _BitacoraCard(entry: entry),
                  ),
                ),
                if (result.lastPage > 1)
                  _PaginationBar(
                    currentPage: result.currentPage,
                    lastPage: result.lastPage,
                    onPrevious: result.currentPage > 1
                        ? () => _goToPage(result.currentPage - 1)
                        : null,
                    onNext: result.currentPage < result.lastPage
                        ? () => _goToPage(result.currentPage + 1)
                        : null,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.result});

  final BitacoraResult result;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.buildPanelDecoration(),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: AppTheme.blue,
            child: Icon(Icons.menu_book_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${result.total} bitácoras registradas',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text('Página ${result.currentPage} de ${result.lastPage}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BitacoraCard extends StatelessWidget {
  const _BitacoraCard({required this.entry});

  final BitacoraEntry entry;

  @override
  Widget build(BuildContext context) {
    final vehicle = [
      entry.vehicleBrand,
      entry.vehicleModel,
    ].where((value) => value.isNotEmpty).join(' ');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.buildSoftCardDecoration(
        backgroundColor: AppTheme.yellowSurface,
        borderRadius: AppTheme.radiusLarge,
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A1B305F),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.driverName.isEmpty
                      ? 'Conductor sin nombre'
                      : entry.driverName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _StatusChip(active: entry.active),
            ],
          ),
          const SizedBox(height: 6),
          _DetailRow(
            icon: Icons.calendar_today_rounded,
            text: BoliviaDateTimeFormatter.format(entry.date),
          ),
          _DetailRow(
            icon: Icons.directions_car_filled_rounded,
            text:
                [
                  if (entry.vehiclePlate.isNotEmpty)
                    'Placa ${entry.vehiclePlate}',
                  if (vehicle.isNotEmpty) vehicle,
                ].join(' · ').isEmpty
                ? 'Vehículo no registrado'
                : [
                    if (entry.vehiclePlate.isNotEmpty)
                      'Placa ${entry.vehiclePlate}',
                    if (vehicle.isNotEmpty) vehicle,
                  ].join(' · '),
          ),
          const Divider(height: 24),
          _RouteRow(
            label: 'Inicio',
            value: entry.startLocation,
            color: AppTheme.successGreen,
          ),
          const SizedBox(height: 10),
          _RouteRow(
            label: 'Destino',
            value: entry.destinationLocation,
            color: AppTheme.errorRed,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricChip(
                icon: Icons.speed_rounded,
                label:
                    '${_formatNumber(entry.resolvedTraveledMileage)} km recorridos',
              ),
              _MetricChip(
                icon: Icons.inventory_2_outlined,
                label: entry.packageCount == null
                    ? 'Paquetes: sin dato'
                    : '${entry.packageCount} paquetes',
              ),
              _MetricChip(
                icon: Icons.local_gas_station_rounded,
                label: entry.fueled
                    ? 'Con abastecimiento'
                    : 'Sin abastecimiento',
              ),
            ],
          ),
          if (entry.driverPhone.isNotEmpty || entry.driverEmail.isNotEmpty) ...[
            const Divider(height: 24),
            if (entry.driverPhone.isNotEmpty)
              _DetailRow(icon: Icons.phone_outlined, text: entry.driverPhone),
            if (entry.driverEmail.isNotEmpty)
              _DetailRow(icon: Icons.email_outlined, text: entry.driverEmail),
          ],
        ],
      ),
    );
  }

  static String _formatNumber(double? value) {
    if (value == null) return 'Sin dato';
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppTheme.successGreen : AppTheme.blueMid;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppTheme.radiusPill,
        border: Border.all(color: color),
      ),
      child: Text(
        active ? 'Activa' : 'Finalizada',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
        Icon(icon, size: 17, color: AppTheme.blueMid),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Icon(Icons.location_on_rounded, size: 19, color: color),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$label: ',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              TextSpan(text: value.isEmpty ? 'Sin información' : value),
            ],
          ),
        ),
      ),
    ],
  );
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: AppTheme.blue.withValues(alpha: 0.08),
      borderRadius: AppTheme.radiusPill,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppTheme.blue),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
      ],
    ),
  );
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.currentPage,
    required this.lastPage,
    required this.onPrevious,
    required this.onNext,
  });
  final int currentPage;
  final int lastPage;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
            label: const Text('Anterior'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            '$currentPage / $lastPage',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onNext,
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.chevron_right_rounded),
            label: const Text('Siguiente'),
          ),
        ),
      ],
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 58,
            color: AppTheme.errorRed,
          ),
          const SizedBox(height: 16),
          const Text(
            'No pudimos cargar las bitácoras.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          const SizedBox(height: 8),
          const Text(
            'Revisa la conexión e intenta nuevamente.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    ),
  );
}
