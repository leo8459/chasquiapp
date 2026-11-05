import 'package:flutter/material.dart';

import 'package:scan_agbc/nucleo/tema/app_theme.dart';
import 'package:scan_agbc/nucleo/utilidades/user_friendly_error_mapper.dart';
import 'package:scan_agbc/nucleo/componentes/app_cards.dart';
import 'package:scan_agbc/nucleo/componentes/app_feedback_banner.dart';
import 'package:scan_agbc/nucleo/componentes/app_page_scaffold.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/available_couriers_result.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/assigned_package_summary.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/courier_summary.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/package_tracking_result.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/repositorios/package_tracking_repository.dart';
import 'package:scan_agbc/funcionalidades/seguimiento/presentacion/paginas/package_tracking_search_page.dart';

class RecentRegionalAssignmentsPage extends StatefulWidget {
  const RecentRegionalAssignmentsPage({
    super.key,
    required this.repository,
    this.initialAssignmentsFuture,
    this.pendingAssignmentsMode = false,
  });

  final PackageTrackingRepository repository;
  final Future<List<AssignedPackageSummary>>? initialAssignmentsFuture;
  final bool pendingAssignmentsMode;

  @override
  State<RecentRegionalAssignmentsPage> createState() =>
      _RecentRegionalAssignmentsPageState();
}

class _RecentRegionalAssignmentsPageState
    extends State<RecentRegionalAssignmentsPage> {
  late Future<List<AssignedPackageSummary>> _future =
      widget.initialAssignmentsFuture ?? _loadAssignments();
  late Future<AvailableCouriersResult> _couriersFuture;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  CourierSummary? _selectedCourier;
  Future<List<AssignedPackageSummary>>? _selectedCourierAssignmentsFuture;
  String _searchQuery = '';
  int? _revertingAssignmentId;

  @override
  void initState() {
    super.initState();
    _couriersFuture = widget.repository.findAvailableCouriers();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<List<AssignedPackageSummary>> _loadAssignments() {
    return widget.pendingAssignmentsMode
        ? widget.repository.findPendingRegionalAssignments().then(
            (summary) => summary.assignments,
          )
        : widget.repository.findRecentRegionalAssignments();
  }

  Future<void> _reload() async {
    final nextFuture = _loadAssignments();
    final selectedCourier = _selectedCourier;
    setState(() {
      _future = nextFuture;
      if (selectedCourier != null) {
        _selectedCourierAssignmentsFuture = _loadCourierAssignments(
          selectedCourier,
        );
      }
    });
    await nextFuture;
  }

  Future<List<AssignedPackageSummary>> _loadCourierAssignments(
    CourierSummary courier,
  ) async {
    final assignments = await widget.repository.findAssignmentsForUser(
      courier.id,
      forceRefresh: true,
    );
    return assignments
        .map(
          (assignment) => assignment.copyWith(
            courierUserId: courier.id,
            courierName: courier.displayName,
          ),
        )
        .toList(growable: false);
  }

  void _selectCourier(CourierSummary? courier) {
    setState(() {
      _selectedCourier = courier;
      _selectedCourierAssignmentsFuture = courier == null
          ? null
          : _loadCourierAssignments(courier);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.minScrollExtent);
      }
    });
  }

  void _setSearchQuery(String value) {
    setState(() {
      _searchQuery = value.trim().toUpperCase();
    });
  }

  Widget _buildFilters() {
    return AppSoftCard(
      padding: const EdgeInsets.all(14),
      backgroundColor: AppTheme.yellowField,
      borderRadius: AppTheme.radiusLarge,
      borderColor: AppTheme.softBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchController,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Buscar por código de paquete',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpiar búsqueda',
                      onPressed: () {
                        _searchController.clear();
                        _setSearchQuery('');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
            onChanged: _setSearchQuery,
          ),
          const SizedBox(height: 12),
          FutureBuilder<AvailableCouriersResult>(
            future: _couriersFuture,
            builder: (context, snapshot) {
              final couriersById = <int, CourierSummary>{};
              for (final courier
                  in snapshot.data?.couriers ?? const <CourierSummary>[]) {
                if (courier.id > 0) {
                  couriersById.putIfAbsent(courier.id, () => courier);
                }
              }
              final selectedCourier = _selectedCourier;
              if (selectedCourier != null && selectedCourier.id > 0) {
                couriersById.putIfAbsent(
                  selectedCourier.id,
                  () => selectedCourier,
                );
              }
              final couriers = couriersById.values.toList(growable: false);
              final selectedCourierId = selectedCourier?.id ?? 0;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<int>(
                    key: ValueKey<int>(selectedCourierId),
                    initialValue: selectedCourierId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Filtrar por cartero',
                      prefixIcon: Icon(Icons.person_search_rounded),
                    ),
                    items: [
                      const DropdownMenuItem<int>(
                        value: 0,
                        child: Text('Todos los carteros'),
                      ),
                      ...couriers.map(
                        (courier) => DropdownMenuItem<int>(
                          value: courier.id,
                          child: Text(
                            courier.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: snapshot.hasData
                        ? (userId) {
                            final selected = userId == null || userId == 0
                                ? null
                                : couriers.firstWhere(
                                    (courier) => courier.id == userId,
                                  );
                            _selectCourier(selected);
                          }
                        : null,
                  ),
                  if (snapshot.connectionState != ConnectionState.done) ...[
                    const SizedBox(height: 10),
                    const LinearProgressIndicator(),
                  ] else if (snapshot.hasError) ...[
                    const SizedBox(height: 8),
                    const Text('No se pudo cargar la lista de carteros.'),
                  ],
                  if (_selectedCourier != null) ...[
                    const SizedBox(height: 10),
                    _buildSelectedCourierPendingCount(),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedCourierPendingCount() {
    final future = _selectedCourierAssignmentsFuture;
    if (future == null) return const SizedBox.shrink();

    return FutureBuilder<List<AssignedPackageSummary>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.blue,
                ),
              ),
              SizedBox(width: 8),
              Text('Consultando pendientes de entrega...'),
            ],
          );
        }
        if (snapshot.hasError) {
          return const Text('No se pudo consultar el total de pendientes.');
        }
        final count = snapshot.data?.length ?? 0;
        final pendingLabel = count == 1
            ? '1 paquete pendiente'
            : '$count paquetes pendientes';
        return Text(
          '${_selectedCourier!.displayName}: $pendingLabel de entrega.',
          style: const TextStyle(
            color: AppTheme.blueDark,
            fontWeight: FontWeight.w900,
          ),
        );
      },
    );
  }

  Widget _buildAssignmentsList(
    List<AssignedPackageSummary> assignments, {
    bool selectedCourierLoading = false,
    Object? selectedCourierError,
  }) {
    final filteredAssignments = assignments
        .where((assignment) {
          if (_searchQuery.isEmpty) return true;
          return assignment.code.toUpperCase().contains(_searchQuery);
        })
        .toList(growable: false);
    final hasNoMatches = filteredAssignments.isEmpty;

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      itemCount: hasNoMatches ? 3 : filteredAssignments.length + 2,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _RecentAssignmentsHeader(
            pendingMode:
                widget.pendingAssignmentsMode || _selectedCourier != null,
            selectedCourierName: _selectedCourier?.displayName,
          );
        }
        if (index == 1) return _buildFilters();
        if (hasNoMatches) {
          final title = selectedCourierLoading
              ? 'Cargando paquetes pendientes'
              : selectedCourierError != null
              ? 'No se pudieron cargar los pendientes'
              : 'No hay paquetes para mostrar';
          final message = selectedCourierLoading
              ? 'Consultando las asignaciones del cartero seleccionado.'
              : selectedCourierError != null
              ? UserFriendlyErrorMapper.message(
                  selectedCourierError,
                  fallback: 'Intenta nuevamente en unos segundos.',
                )
              : _searchQuery.isNotEmpty
              ? 'No encontramos paquetes con el código "$_searchQuery".'
              : _selectedCourier != null
              ? 'Este cartero no tiene paquetes pendientes de entrega.'
              : widget.pendingAssignmentsMode
              ? 'No hay paquetes asignados pendientes en tu departamento.'
              : 'No hay paquetes asignados recientes para tu región.';
          return AppStatusMessageCard(
            title: title,
            message: message,
            icon: selectedCourierLoading
                ? Icons.hourglass_top_rounded
                : Icons.inventory_2_outlined,
          );
        }

        final assignment = filteredAssignments[index - 2];
        return _RegionalAssignmentCard(
          assignment: assignment,
          reverting: _revertingAssignmentId == assignment.assignmentId,
          allowRevert: !widget.pendingAssignmentsMode,
          onOpenDetails: () => _openPackageDetails(assignment),
          onRevert: () => _revertAssignment(assignment),
        );
      },
    );
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
      title: _selectedCourier != null
          ? 'Pendientes por cartero'
          : widget.pendingAssignmentsMode
          ? 'Paquetes pendientes asignados'
          : 'Asignaciones recientes',
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
                    title: widget.pendingAssignmentsMode
                        ? 'No se pudieron cargar los pendientes'
                        : 'No se pudo cargar el historial',
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
            final selectedCourier = _selectedCourier;
            if (selectedCourier == null) {
              return _buildAssignmentsList(assignments);
            }

            return FutureBuilder<List<AssignedPackageSummary>>(
              future: _selectedCourierAssignmentsFuture,
              builder: (context, courierSnapshot) => _buildAssignmentsList(
                courierSnapshot.data ?? const <AssignedPackageSummary>[],
                selectedCourierLoading:
                    courierSnapshot.connectionState != ConnectionState.done,
                selectedCourierError: courierSnapshot.error,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RecentAssignmentsHeader extends StatelessWidget {
  const _RecentAssignmentsHeader({
    this.pendingMode = false,
    this.selectedCourierName,
  });

  final bool pendingMode;
  final String? selectedCourierName;

  @override
  Widget build(BuildContext context) {
    return AppSoftCard(
      padding: const EdgeInsets.all(18),
      backgroundColor: AppTheme.blue,
      borderRadius: AppTheme.radiusLarge,
      borderColor: AppTheme.strongBorder,
      child: Row(
        children: [
          _HeaderIcon(),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedCourierName != null
                      ? 'Pendientes de $selectedCourierName'
                      : pendingMode
                      ? 'Pendientes del departamento'
                      : 'Historial regional',
                  style: TextStyle(
                    color: AppTheme.yellowLight,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  selectedCourierName != null
                      ? 'Paquetes pendientes de entrega asignados a este cartero.'
                      : pendingMode
                      ? 'Paquetes asignados que siguen pendientes de entrega.'
                      : 'Solo paquetes asignados hoy en estado CARTERO.',
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
    required this.allowRevert,
    required this.onOpenDetails,
    required this.onRevert,
  });

  final AssignedPackageSummary assignment;
  final bool reverting;
  final bool allowRevert;
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
          final detailAction = _HistoryActionButton(
            icon: Icons.visibility_rounded,
            label: 'Ver detalle',
            backgroundColor: AppTheme.blue,
            foregroundColor: AppTheme.yellowLight,
            onPressed: onOpenDetails,
          );
          final revertAction = _HistoryActionButton(
            icon: reverting ? null : Icons.undo_rounded,
            label: 'ALMACEN',
            backgroundColor: AppTheme.actionYellowStrong,
            foregroundColor: AppTheme.blueDark,
            busy: reverting,
            onPressed: reverting ? null : onRevert,
          );

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
                  children: allowRevert
                      ? [
                          Expanded(child: detailAction),
                          const SizedBox(width: 10),
                          Expanded(child: revertAction),
                        ]
                      : [Expanded(child: detailAction)],
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
                child: allowRevert
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          detailAction,
                          const SizedBox(height: 8),
                          revertAction,
                        ],
                      )
                    : detailAction,
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
