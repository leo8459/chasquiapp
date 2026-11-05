import 'package:flutter/material.dart';

import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/pending_assignments_summary.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/repositorios/package_tracking_repository.dart';
import 'package:scan_agbc/nucleo/tema/app_theme.dart';

class PendingAssignmentsAlertPanel extends StatefulWidget {
  const PendingAssignmentsAlertPanel({
    super.key,
    required this.repository,
    required this.initialSummaryFuture,
    required this.onOpenAssignments,
  });

  final PackageTrackingRepository repository;
  final Future<PendingAssignmentsSummary> initialSummaryFuture;
  final ValueChanged<PendingAssignmentsSummary> onOpenAssignments;

  @override
  State<PendingAssignmentsAlertPanel> createState() =>
      _PendingAssignmentsAlertPanelState();
}

class _PendingAssignmentsAlertPanelState
    extends State<PendingAssignmentsAlertPanel> {
  late Future<PendingAssignmentsSummary> _summaryFuture =
      widget.initialSummaryFuture;

  @override
  void didUpdateWidget(covariant PendingAssignmentsAlertPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
      oldWidget.initialSummaryFuture,
      widget.initialSummaryFuture,
    )) {
      _summaryFuture = widget.initialSummaryFuture;
    }
  }

  Future<void> _reload() async {
    final nextFuture = widget.repository.findPendingRegionalAssignments();
    setState(() {
      _summaryFuture = nextFuture;
    });
    await nextFuture;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PendingAssignmentsSummary>(
      future: _summaryFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _AlertCard(
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.blue,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Cargando alertas de paquetes pendientes...'),
                ),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return _AlertCard(
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: AppTheme.errorRed,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'No se pudieron cargar las alertas de pendientes.',
                  ),
                ),
                IconButton(
                  tooltip: 'Reintentar',
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          );
        }

        final summary = snapshot.data!;
        final department = summary.departmentName.trim().isEmpty
            ? 'tu departamento'
            : summary.departmentName;
        final visibleAssignments = summary.assignments.take(3).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AlertCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.notification_important_rounded,
                        color: AppTheme.errorRed,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Paquetes asignados pendientes',
                          style: TextStyle(
                            color: AppTheme.blueDark,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      _CountBadge(count: summary.pendingTotal),
                      IconButton(
                        tooltip: 'Actualizar alertas',
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  if (visibleAssignments.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    ...visibleAssignments.map(
                      (assignment) => Padding(
                        padding: const EdgeInsets.only(left: 34, bottom: 3),
                        child: Text(
                          '${assignment.code} · ${assignment.safeCourierName} · ${assignment.stateName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.blueDark,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    const Padding(
                      padding: EdgeInsets.only(left: 34, top: 4),
                      child: Text(
                        'No hay paquetes asignados pendientes.',
                        style: TextStyle(color: AppTheme.blueDark),
                      ),
                    ),
                  ],
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => widget.onOpenAssignments(summary),
                      icon: const Icon(Icons.list_alt_rounded),
                      label: const Text('Ver paquetes'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _AlertCard(
              backgroundColor: AppTheme.blue,
              child: Row(
                children: [
                  const Icon(
                    Icons.account_balance_outlined,
                    color: AppTheme.yellowLight,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Total pendiente asignado · $department',
                      style: const TextStyle(
                        color: AppTheme.yellowLight,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _CountBadge(count: summary.pendingTotal, dark: true),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.child, this.backgroundColor});

  final Widget child;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor ?? AppTheme.yellowField,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.softBorder),
      ),
      child: child,
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, this.dark = false});

  final int count;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 34, minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: dark ? AppTheme.actionYellowStrong : AppTheme.errorRed,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          color: dark ? AppTheme.blueDark : Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
