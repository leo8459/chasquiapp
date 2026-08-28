import 'package:flutter/material.dart';

import 'package:scan_agbc/nucleo/tema/app_theme.dart';
import 'package:scan_agbc/nucleo/utilidades/user_friendly_error_mapper.dart';
import 'package:scan_agbc/nucleo/componentes/app_cards.dart';
import 'package:scan_agbc/nucleo/componentes/app_feedback_banner.dart';
import 'package:scan_agbc/nucleo/componentes/app_page_scaffold.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/assigned_package_summary.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/package_tracking_result.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/repositorios/package_tracking_repository.dart';
import 'package:scan_agbc/funcionalidades/seguimiento/presentacion/paginas/package_tracking_search_page.dart';

class RecentRegionalAssignmentsPage extends StatefulWidget {
  const RecentRegionalAssignmentsPage({
    super.key,
    required this.repository,
    this.initialAssignmentsFuture,
  });

  final PackageTrackingRepository repository;
  final Future<List<AssignedPackageSummary>>? initialAssignmentsFuture;

  @override
  State<RecentRegionalAssignmentsPage> createState() =>
      _RecentRegionalAssignmentsPageState();
}

class _RecentRegionalAssignmentsPageState
    extends State<RecentRegionalAssignmentsPage> {
  late Future<List<AssignedPackageSummary>> _future =
      widget.initialAssignmentsFuture ?? _loadAssignments();
  int? _revertingAssignmentId;

  Future<List<AssignedPackageSummary>> _loadAssignments() {
    return widget.repository.findRecentRegionalAssignments();
  }

  Future<void> _reload() async {
    final nextFuture = _loadAssignments();
    setState(() {
      _future = nextFuture;
    });
    await nextFuture;
  }

  Future<void> _openPackageDetails(AssignedPackageSummary assignment) async {
    final initialLookupFuture = widget.repository.findByCode(assignment.code);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PackageTrackingSearchPage(
          repository: widget.repository,
          initialCode: assignment.code,
          initialLookupFuture: initialLookupFuture,
        ),
      ),
    );
  }

  Future<void> _revertAssignment(AssignedPackageSummary assignment) async {
    if (_revertingAssignmentId != null) return;

    final shouldRevert = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Volver a ALMACEN'),
          content: Text(
            'Se quitara ${assignment.code} de ${assignment.safeCourierName.toUpperCase()} y volvera a ALMACEN.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Volver a ALMACEN'),
            ),
          ],
        );
      },
    );

    if (shouldRevert != true || !mounted) return;

    setState(() {
      _revertingAssignmentId = assignment.assignmentId;
    });

    try {
      await widget.repository.revertAssignmentToWarehouse(
        courierUserId: assignment.courierUserId,
        assignmentId: assignment.assignmentId,
      );
      if (!mounted) return;
      showAppFeedbackBanner(
        context,
        'Asignacion revertida. El paquete volvio a ALMACEN.',
        tone: AppFeedbackTone.success,
      );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      showAppFeedbackBanner(
        context,
        UserFriendlyErrorMapper.message(
          error,
          fallback: 'No pudimos revertir la asignación. Intenta nuevamente.',
        ),
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _revertingAssignmentId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: 'Asignaciones recientes',
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<AssignedPackageSummary>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(color: AppTheme.blue),
              );
            }

            if (snapshot.hasError) {
              return ListView(
                padding: AppTheme.pagePadding,
                children: [
                  AppStatusMessageCard(
                    title: 'No se pudo cargar el historial',
                    message: UserFriendlyErrorMapper.message(
                      snapshot.error,
                      fallback: 'Intenta nuevamente en unos segundos.',
                    ),
                    icon: Icons.error_outline_rounded,
                    iconColor: AppTheme.errorRed,
                  ),
                ],
              );
            }

            final assignments =
                snapshot.data ?? const <AssignedPackageSummary>[];
            if (assignments.isEmpty) {
              return ListView(
                padding: AppTheme.pagePadding,
                children: const [
                  AppStatusMessageCard(
                    title: 'Sin asignaciones recientes',
                    message:
                        'No hay paquetes asignados hoy en estado CARTERO para tu región.',
                    icon: Icons.history_rounded,
                  ),
                ],
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              itemCount: assignments.length + 1,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return const _RecentAssignmentsHeader();
                }

                final assignment = assignments[index - 1];
                return _RegionalAssignmentCard(
                  assignment: assignment,
                  reverting: _revertingAssignmentId == assignment.assignmentId,
                  onOpenDetails: () => _openPackageDetails(assignment),
                  onRevert: () => _revertAssignment(assignment),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _RecentAssignmentsHeader extends StatelessWidget {
  const _RecentAssignmentsHeader();

  @override
  Widget build(BuildContext context) {
    return AppSoftCard(
      padding: const EdgeInsets.all(18),
      backgroundColor: AppTheme.blue,
      borderRadius: AppTheme.radiusLarge,
      borderColor: AppTheme.strongBorder,
      child: const Row(
        children: [
          _HeaderIcon(),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Historial regional',
                  style: TextStyle(
                    color: AppTheme.yellowLight,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Solo paquetes asignados hoy en estado CARTERO.',
                  style: TextStyle(
                    color: AppTheme.yellowLight,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.actionYellowStrong,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.strongBorder, width: 1.5),
      ),
      child: const Icon(
        Icons.history_rounded,
        color: AppTheme.blueDark,
        size: 27,
      ),
    );
  }
}

class _RegionalAssignmentCard extends StatelessWidget {
  const _RegionalAssignmentCard({
    required this.assignment,
    required this.reverting,
    required this.onOpenDetails,
    required this.onRevert,
  });

  final AssignedPackageSummary assignment;
  final bool reverting;
  final VoidCallback onOpenDetails;
  final VoidCallback onRevert;

  @override
  Widget build(BuildContext context) {
    return AppSoftCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      backgroundColor: AppTheme.yellowField,
      borderRadius: AppTheme.radiusLarge,
      borderColor: AppTheme.softBorder,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 430;
          final info = _AssignmentInfoBlock(assignment: assignment);
          final actions = [
            _HistoryActionButton(
              icon: Icons.visibility_rounded,
              label: 'Ver detalle',
              backgroundColor: AppTheme.blue,
              foregroundColor: AppTheme.yellowLight,
              onPressed: onOpenDetails,
            ),
            _HistoryActionButton(
              icon: reverting ? null : Icons.undo_rounded,
              label: 'ALMACEN',
              backgroundColor: AppTheme.actionYellowStrong,
              foregroundColor: AppTheme.blueDark,
              busy: reverting,
              onPressed: reverting ? null : onRevert,
            ),
          ];

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 82,
                      height: 82,
                      child: Image.asset(
                        'assets/images/package_box.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: info),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: actions.first),
                    const SizedBox(width: 10),
                    Expanded(child: actions.last),
                  ],
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 76,
                height: 76,
                child: Image.asset(
                  'assets/images/package_box.png',
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: info),
              const SizedBox(width: 12),
              SizedBox(
                width: 118,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    actions.first,
                    const SizedBox(height: 8),
                    actions.last,
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AssignmentInfoBlock extends StatelessWidget {
  const _AssignmentInfoBlock({required this.assignment});

  final AssignedPackageSummary assignment;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          assignment.code,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.titleMedium?.copyWith(
            color: AppTheme.blueDark,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          assignment.safeCourierName.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.bodyMedium?.copyWith(
            color: AppTheme.blueDark,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _InfoChip(
              icon: Icons.local_shipping_rounded,
              label: assignment.category.label,
            ),
            _InfoChip(
              icon: Icons.assignment_turned_in_rounded,
              label: assignment.stateName.toUpperCase(),
            ),
            _InfoChip(
              icon: Icons.schedule_rounded,
              label: assignment.formattedDate,
            ),
          ],
        ),
      ],
    );
  }
}

class _HistoryActionButton extends StatelessWidget {
  const _HistoryActionButton({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onPressed,
    this.icon,
    this.busy = false,
  });

  final String label;
  final IconData? icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        disabledBackgroundColor: backgroundColor.withValues(alpha: 0.55),
        disabledForegroundColor: foregroundColor,
        minimumSize: const Size.fromHeight(36),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy)
            SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: foregroundColor,
              ),
            )
          else if (icon != null)
            Icon(icon, size: 16),
          if (busy || icon != null) const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.yellowLight,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x80C9B58B)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.blueMid),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.blueMid,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
