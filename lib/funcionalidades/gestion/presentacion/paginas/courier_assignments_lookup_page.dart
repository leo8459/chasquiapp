import 'package:flutter/material.dart';

import 'package:scan_agbc/nucleo/tema/app_theme.dart';
import 'package:scan_agbc/nucleo/utilidades/user_friendly_error_mapper.dart';
import 'package:scan_agbc/nucleo/componentes/app_cards.dart';
import 'package:scan_agbc/nucleo/componentes/app_page_scaffold.dart';
import 'package:scan_agbc/nucleo/componentes/app_view_mode_toggle.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/available_couriers_result.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/courier_summary.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/repositorios/package_tracking_repository.dart';
import 'package:scan_agbc/funcionalidades/cartero/presentacion/paginas/assigned_packages_page.dart';
import 'package:scan_agbc/funcionalidades/gestion/presentacion/paginas/courier_inventory_assignment_page.dart';

enum CourierLookupMode { assignPackages, viewAssignments }

enum _CourierSortOption { assignmentsDesc, assignmentsAsc, nameAsc, nameDesc }

extension _CourierSortOptionX on _CourierSortOption {
  String get label {
    switch (this) {
      case _CourierSortOption.assignmentsDesc:
        return 'Más asignaciones';
      case _CourierSortOption.assignmentsAsc:
        return 'Menos asignaciones';
      case _CourierSortOption.nameAsc:
        return 'Nombre A-Z';
      case _CourierSortOption.nameDesc:
        return 'Nombre Z-A';
    }
  }

  IconData get icon {
    switch (this) {
      case _CourierSortOption.assignmentsDesc:
        return Icons.arrow_downward_rounded;
      case _CourierSortOption.assignmentsAsc:
        return Icons.arrow_upward_rounded;
      case _CourierSortOption.nameAsc:
        return Icons.sort_by_alpha_rounded;
      case _CourierSortOption.nameDesc:
        return Icons.swap_vert_rounded;
    }
  }
}

class CourierAssignmentsLookupPage extends StatefulWidget {
  const CourierAssignmentsLookupPage({
    super.key,
    required this.repository,
    this.onScanCodeWithCamera,
    this.onScanCodesWithCamera,
    this.initialCouriersFuture,
    this.mode = CourierLookupMode.assignPackages,
  });

  final PackageTrackingRepository repository;
  final Future<String?> Function()? onScanCodeWithCamera;
  final Future<List<String>?> Function(
    Set<String> availablePackageCodes,
    Set<String> initiallySelectedCodes,
    ValueChanged<Set<String>> onSelectedCodesChanged,
    Future<List<String>?> Function(List<String> selectedCodes)
    onReviewSelectedCodes,
  )?
  onScanCodesWithCamera;
  final Future<AvailableCouriersResult>? initialCouriersFuture;
  final CourierLookupMode mode;

  @override
  State<CourierAssignmentsLookupPage> createState() =>
      _CourierAssignmentsLookupPageState();
}

class _CourierAssignmentsLookupPageState
    extends State<CourierAssignmentsLookupPage> {
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocusNode = FocusNode();
  _CourierSortOption _currentSort = _CourierSortOption.assignmentsDesc;
  bool _preferGridLayout = true;
  List<CourierSummary>? _visibleCouriersCacheSource;
  String? _visibleCouriersCacheQuery;
  _CourierSortOption? _visibleCouriersCacheSort;
  List<CourierSummary>? _visibleCouriersCacheValue;
  final Map<int, String> _courierSearchTextCache = <int, String>{};
  final Map<int, String> _courierSortNameCache = <int, String>{};

  late Future<AvailableCouriersResult> _couriersFuture =
      widget.initialCouriersFuture ?? _loadCouriers();

  bool get _viewAssignmentsMode =>
      widget.mode == CourierLookupMode.viewAssignments;

  String get _pageTitle =>
      _viewAssignmentsMode ? 'Carteros' : 'Asignar paquetes';

  String get _searchTitle =>
      _viewAssignmentsMode ? 'Buscar cartero' : 'Buscar por nombre';

  String get _searchHint => _viewAssignmentsMode
      ? 'Nombre, correo o CI del cartero'
      : 'Escribe el nombre del cartero';

  String get _couriersSectionTitle =>
      _viewAssignmentsMode ? 'Todos los carteros' : 'Carteros disponibles';

  String get _courierActionLabel =>
      _viewAssignmentsMode ? 'Ver asign.' : 'Asignar';

  IconData get _courierActionIcon =>
      _viewAssignmentsMode ? Icons.assignment_rounded : Icons.add_task_rounded;

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  Future<AvailableCouriersResult> _loadCouriers({bool forceRefresh = false}) {
    return widget.repository.findAvailableCouriers(
      forceRefresh: forceRefresh,
      allCities: _viewAssignmentsMode,
    );
  }

  void _refreshCouriers() {
    _clearCourierCaches();
    setState(() {
      _couriersFuture = _loadCouriers(forceRefresh: true);
    });
  }

  String _normalizeSearchText(String rawText) {
    return rawText.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<void> _openCourierInventory(CourierSummary courier) async {
    final initialPackagesFuture = widget.repository
        .findInventoryPackagesForCourier(courier.id);
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => CourierInventoryAssignmentPage(
          courier: courier,
          repository: widget.repository,
          onScanCodeWithCamera: widget.onScanCodeWithCamera,
          onScanCodesWithCamera: widget.onScanCodesWithCamera,
          initialPackagesFuture: initialPackagesFuture,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curvedAnimation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.045, 0),
                end: Offset.zero,
              ).animate(curvedAnimation),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 150),
      ),
    );

    if (!mounted) return;
    _clearCourierCaches();
    setState(() {
      _couriersFuture = _loadCouriers();
    });
  }

  Future<void> _openCourierAssignments(CourierSummary courier) async {
    final initialAssignmentsFuture = widget.repository.findAssignmentsForUser(
      courier.id,
    );
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => AssignedPackagesPage(
          userId: courier.id,
          courierName: courier.displayName,
          repository: widget.repository,
          initialAssignmentsFuture: initialAssignmentsFuture,
          allowStatusToggle: true,
          onScanCodeWithCamera: widget.onScanCodeWithCamera,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curvedAnimation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.045, 0),
                end: Offset.zero,
              ).animate(curvedAnimation),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 150),
      ),
    );

    if (!mounted) return;
    _clearCourierCaches();
    setState(() {
      _couriersFuture = _loadCouriers(forceRefresh: true);
    });
  }

  Future<void> _openCourier(CourierSummary courier) {
    return _viewAssignmentsMode
        ? _openCourierAssignments(courier)
        : _openCourierInventory(courier);
  }

  List<CourierSummary> _visibleCouriers(List<CourierSummary> couriers) {
    final query = _normalizeSearchText(_nameController.text);
    final cachedValue = _visibleCouriersCacheValue;
    if (cachedValue != null &&
        identical(_visibleCouriersCacheSource, couriers) &&
        _visibleCouriersCacheQuery == query &&
        _visibleCouriersCacheSort == _currentSort) {
      return cachedValue;
    }

    final result = query.isEmpty
        ? couriers.toList(growable: false)
        : couriers
              .where((courier) {
                return _searchableTextFor(courier).contains(query);
              })
              .toList(growable: false);

    result.sort(_compareCouriers);
    _visibleCouriersCacheSource = couriers;
    _visibleCouriersCacheQuery = query;
    _visibleCouriersCacheSort = _currentSort;
    _visibleCouriersCacheValue = result;
    return result;
  }

  void _clearCourierCaches() {
    _visibleCouriersCacheSource = null;
    _visibleCouriersCacheQuery = null;
    _visibleCouriersCacheSort = null;
    _visibleCouriersCacheValue = null;
    _courierSearchTextCache.clear();
    _courierSortNameCache.clear();
  }

  String _searchableTextFor(CourierSummary courier) {
    return _courierSearchTextCache.putIfAbsent(
      courier.id,
      () => _normalizeSearchText(
        '${courier.displayName} ${courier.email} ${courier.ci}',
      ),
    );
  }

  String _sortNameFor(CourierSummary courier) {
    return _courierSortNameCache.putIfAbsent(
      courier.id,
      () => _normalizeSearchText(courier.displayName),
    );
  }

  int _compareCouriers(CourierSummary first, CourierSummary second) {
    final nameComparison = _compareCourierNames(first, second);
    final assignmentComparison = first.activeAssignmentsCount.compareTo(
      second.activeAssignmentsCount,
    );

    switch (_currentSort) {
      case _CourierSortOption.assignmentsDesc:
        return assignmentComparison == 0
            ? nameComparison
            : -assignmentComparison;
      case _CourierSortOption.assignmentsAsc:
        return assignmentComparison == 0
            ? nameComparison
            : assignmentComparison;
      case _CourierSortOption.nameAsc:
        return nameComparison == 0 ? -assignmentComparison : nameComparison;
      case _CourierSortOption.nameDesc:
        return nameComparison == 0 ? -assignmentComparison : -nameComparison;
    }
  }

  int _compareCourierNames(CourierSummary first, CourierSummary second) {
    return _sortNameFor(first).compareTo(_sortNameFor(second));
  }

  String _mapError(Object error) {
    return UserFriendlyErrorMapper.message(
      error,
      fallback:
          'No pudimos cargar la información de carteros en este momento. Intenta nuevamente.',
    );
  }

  Future<void> _openSortSheet() async {
    final selected = await showModalBottomSheet<_CourierSortOption>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (context) {
        final textTheme = Theme.of(context).textTheme;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.blue,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                  bottom: Radius.circular(28),
                ),
                border: Border.all(color: AppTheme.strongBorder),
                boxShadow: const [
                  BoxShadow(
                    color: AppTheme.strongShadow,
                    blurRadius: 20,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.actionYellowStrong,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Ordenado por',
                      style: textTheme.titleMedium?.copyWith(
                        color: AppTheme.actionYellowStrong,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ..._CourierSortOption.values.map((option) {
                      final isSelected = option == _currentSort;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: AppTheme.radiusLarge,
                            onTap: () => Navigator.of(context).pop(option),
                            child: Ink(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppTheme.actionYellowStrong.withValues(
                                        alpha: 0.09,
                                      )
                                    : Colors.transparent,
                                borderRadius: AppTheme.radiusLarge,
                                border: Border.all(
                                  color: isSelected
                                      ? AppTheme.actionYellowStrong
                                      : AppTheme.yellowField.withValues(
                                          alpha: 0.25,
                                        ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    option.icon,
                                    size: 20,
                                    color: isSelected
                                        ? AppTheme.actionYellowStrong
                                        : AppTheme.yellowField,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      option.label,
                                      style: textTheme.labelLarge?.copyWith(
                                        color: isSelected
                                            ? AppTheme.actionYellowStrong
                                            : AppTheme.yellowField,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    isSelected
                                        ? Icons.check_rounded
                                        : Icons.chevron_right_rounded,
                                    color: isSelected
                                        ? AppTheme.actionYellowStrong
                                        : AppTheme.yellowField,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    if (!mounted || selected == null || selected == _currentSort) {
      return;
    }

    setState(() {
      _currentSort = selected;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AppPageScaffold(
      resizeToAvoidBottomInset: false,
      title: _pageTitle,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openSortSheet,
        backgroundColor: AppTheme.blue,
        foregroundColor: AppTheme.yellowLight,
        icon: const Icon(Icons.filter_list_rounded),
        label: const Text(
          'Ordenado por',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: FutureBuilder<AvailableCouriersResult>(
        future: _couriersFuture,
        builder: (context, snapshot) {
          Future<void> refresh() async {
            _refreshCouriers();
            await _couriersFuture;
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return RefreshIndicator(
              onRefresh: refresh,
              child: const CustomScrollView(
                physics: AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: CircularProgressIndicator(color: AppTheme.blue),
                    ),
                  ),
                ],
              ),
            );
          }

          if (snapshot.hasError) {
            return RefreshIndicator(
              onRefresh: refresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: AppTheme.pagePadding,
                    sliver: SliverToBoxAdapter(
                      child: AppPanelCard(
                        borderRadius: AppTheme.radiusXLarge,
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'No pudimos cargar los carteros.',
                                style: textTheme.titleMedium?.copyWith(
                                  color: AppTheme.blue,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _mapError(snapshot.error!),
                                style: textTheme.bodyMedium?.copyWith(
                                  color: AppTheme.blueDark,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: OutlinedButton.icon(
                                  onPressed: _refreshCouriers,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Reintentar'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          final result =
              snapshot.data ??
              const AvailableCouriersResult(
                city: '',
                couriers: <CourierSummary>[],
              );
          final filteredCouriers = _visibleCouriers(result.couriers);
          final hasActiveFilter = _nameController.text.trim().isNotEmpty;
          final availabilityLabel = hasActiveFilter
              ? 'Mostrando ${filteredCouriers.length} de ${result.total} carteros disponibles'
              : '${result.total} carteros disponibles';

          return LayoutBuilder(
            builder: (context, constraints) {
              final canUseGrid = constraints.maxWidth >= 720;
              final useTwoColumns = canUseGrid && _preferGridLayout;

              return RefreshIndicator(
                onRefresh: refresh,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                      sliver: SliverToBoxAdapter(
                        child: _ManagementCitySummaryCard(
                          title: _viewAssignmentsMode
                              ? 'Alcance de consulta'
                              : 'Ciudad de gestión asignada',
                          city: result.safeCity,
                          availabilityLabel: availabilityLabel,
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      sliver: SliverToBoxAdapter(
                        child: AppPanelCard(
                          borderRadius: AppTheme.radiusLarge,
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                          backgroundColor: AppTheme.yellowField,
                          borderColor: AppTheme.softBorder,
                          boxShadow: const [
                            BoxShadow(
                              color: AppTheme.softShadow,
                              blurRadius: 14,
                              offset: Offset(0, 6),
                            ),
                          ],
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _searchTitle,
                                style: textTheme.titleSmall?.copyWith(
                                  color: AppTheme.blue,
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _nameController,
                                focusNode: _nameFocusNode,
                                textInputAction: TextInputAction.search,
                                onChanged: (_) {
                                  _visibleCouriersCacheValue = null;
                                  setState(() {});
                                },
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  prefixIconConstraints: const BoxConstraints(
                                    minWidth: 42,
                                    minHeight: 40,
                                  ),
                                  hintText: _searchHint,
                                  prefixIcon: const Icon(
                                    Icons.person_search_rounded,
                                  ),
                                  suffixIcon:
                                      _nameController.text.trim().isEmpty
                                      ? null
                                      : IconButton(
                                          onPressed: () {
                                            _nameController.clear();
                                            _visibleCouriersCacheValue = null;
                                            setState(() {});
                                          },
                                          icon: const Icon(Icons.close_rounded),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                      sliver: SliverToBoxAdapter(
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _couriersSectionTitle,
                                style: textTheme.titleLarge?.copyWith(
                                  color: AppTheme.blue,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.groups_2_rounded,
                              color: AppTheme.blue,
                              size: 22,
                            ),
                            if (canUseGrid) ...[
                              const SizedBox(width: 10),
                              AppViewModeToggle(
                                gridEnabled: useTwoColumns,
                                onGridEnabledChanged: (enabled) {
                                  setState(() => _preferGridLayout = enabled);
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (filteredCouriers.isEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        sliver: SliverToBoxAdapter(
                          child: AppPanelCard(
                            borderRadius: AppTheme.radiusXLarge,
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Text(
                                hasActiveFilter
                                    ? 'No encontramos carteros con ese nombre en ${result.safeCity}.'
                                    : 'No hay carteros disponibles en ${result.safeCity} en este momento.',
                                style: textTheme.bodyMedium?.copyWith(
                                  color: AppTheme.blueDark,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    else if (useTwoColumns)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        sliver: SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 10,
                                mainAxisExtent: constraints.maxWidth >= 820
                                    ? 178
                                    : 160,
                              ),
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final courier = filteredCouriers[index];
                            return _CourierSummaryCard(
                              key: ValueKey<int>(courier.id),
                              courier: courier,
                              actionLabel: _courierActionLabel,
                              actionIcon: _courierActionIcon,
                              onTap: () => _openCourier(courier),
                            );
                          }, childCount: filteredCouriers.length),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        sliver: SliverFixedExtentList.builder(
                          itemExtent: 158,
                          itemCount: filteredCouriers.length,
                          itemBuilder: (context, index) {
                            final courier = filteredCouriers[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _CourierSummaryCard(
                                key: ValueKey<int>(courier.id),
                                courier: courier,
                                actionLabel: _courierActionLabel,
                                actionIcon: _courierActionIcon,
                                onTap: () => _openCourier(courier),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ManagementCitySummaryCard extends StatelessWidget {
  const _ManagementCitySummaryCard({
    required this.title,
    required this.city,
    required this.availabilityLabel,
  });

  final String title;
  final String city;
  final String availabilityLabel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.blueDark, AppTheme.blue, AppTheme.blueMid],
        ),
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(
          color: AppTheme.actionYellowStrong.withValues(alpha: 0.5),
          width: AppTheme.borderWidth,
        ),
        boxShadow: const [
          BoxShadow(
            color: AppTheme.strongShadow,
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.actionYellowStrong,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppTheme.yellowField.withValues(alpha: 0.4),
                  ),
                ),
                child: const Icon(
                  Icons.location_city_rounded,
                  color: AppTheme.blueDark,
                  size: 23,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.labelMedium?.copyWith(
                        color: AppTheme.yellowField,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      city,
                      style: textTheme.titleLarge?.copyWith(
                        color: AppTheme.yellowField,
                        letterSpacing: 0,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppTheme.yellowField.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.yellowField.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.assignment_ind_rounded,
                  color: AppTheme.actionYellowStrong,
                  size: 19,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    availabilityLabel,
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppTheme.yellowField,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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

class _CourierSummaryCard extends StatelessWidget {
  const _CourierSummaryCard({
    super.key,
    required this.courier,
    required this.actionLabel,
    required this.actionIcon,
    required this.onTap,
  });

  final CourierSummary courier;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppTheme.radiusLarge,
            child: Ink(
              decoration: AppTheme.buildSoftCardDecoration(
                backgroundColor: AppTheme.yellowField,
                borderRadius: AppTheme.radiusLarge,
                borderColor: AppTheme.softBorder,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final horizontal = constraints.maxWidth >= 520;
                  final comfortableGrid =
                      !horizontal && constraints.maxWidth >= 260;
                  final avatar = _CourierAvatar(
                    label: _initialsFor(courier.displayName),
                    large: horizontal,
                    comfortable: comfortableGrid,
                  );
                  final details = _CourierDetails(
                    courier: courier,
                    textTheme: textTheme,
                    maxNameLines: horizontal ? 1 : 2,
                    compact: !horizontal && !comfortableGrid,
                  );
                  final roleChip = _CourierMetaChip(
                    icon: Icons.work_outline_rounded,
                    label: courier.roleLabel,
                    emphasized: true,
                    maxWidth: horizontal ? 240 : (comfortableGrid ? 154 : 124),
                  );

                  if (horizontal) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                      child: Row(
                        children: [
                          avatar,
                          const SizedBox(width: 18),
                          Container(
                            width: 1.4,
                            height: 86,
                            color: AppTheme.actionYellowStrong.withValues(
                              alpha: 0.32,
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                details,
                                const SizedBox(height: 9),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: roleChip,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 18),
                          Container(
                            width: 1.4,
                            height: 76,
                            color: AppTheme.actionYellowStrong.withValues(
                              alpha: 0.32,
                            ),
                          ),
                          const SizedBox(width: 18),
                          _AssignCourierButton(
                            label: actionLabel,
                            icon: actionIcon,
                          ),
                        ],
                      ),
                    );
                  }

                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      comfortableGrid ? 14 : 12,
                      comfortableGrid ? 12 : 10,
                      comfortableGrid ? 14 : 12,
                      comfortableGrid ? 14 : 12,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            avatar,
                            SizedBox(width: comfortableGrid ? 12 : 11),
                            Expanded(child: details),
                          ],
                        ),
                        SizedBox(height: comfortableGrid ? 9 : 7),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: roleChip,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _AssignCourierButton(
                              label: actionLabel,
                              icon: actionIcon,
                              compact: true,
                              comfortable: comfortableGrid,
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        if (courier.activeAssignmentsCount > 0)
          Positioned(
            top: -8,
            right: -7,
            child: _AssignmentsCountBadge(
              count: courier.activeAssignmentsCount,
            ),
          ),
      ],
    );
  }

  String _initialsFor(String value) {
    final words = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    if (words.isEmpty) {
      return 'C';
    }

    final first = words.first.characters.first;
    final second = words.length > 1 ? words[1].characters.first : '';
    return '$first$second'.toUpperCase();
  }
}

class _CourierDetails extends StatelessWidget {
  const _CourierDetails({
    required this.courier,
    required this.textTheme,
    required this.maxNameLines,
    this.compact = false,
  });

  final CourierSummary courier;
  final TextTheme textTheme;
  final int maxNameLines;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final email = courier.email.isEmpty
        ? 'Sin correo registrado'
        : courier.email;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          courier.displayName.toUpperCase(),
          style: textTheme.titleMedium?.copyWith(
            color: AppTheme.blueDark,
            fontWeight: FontWeight.w900,
            height: 1.03,
            letterSpacing: 0,
          ),
          maxLines: maxNameLines,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: compact ? 5 : 8),
        Row(
          children: [
            Container(
              width: compact ? 21 : 26,
              height: compact ? 21 : 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.yellowSurface,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppTheme.lightBorder),
              ),
              child: Icon(
                Icons.mail_outline_rounded,
                color: AppTheme.blueDark,
                size: compact ? 14 : 17,
              ),
            ),
            SizedBox(width: compact ? 6 : 8),
            Expanded(
              child: Text(
                email,
                style: textTheme.bodyMedium?.copyWith(
                  color: AppTheme.blueMid,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AssignmentsCountBadge extends StatelessWidget {
  const _AssignmentsCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.errorRed,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.errorRed),
      ),
      child: Semantics(
        label: count == 1 ? '1 asignación' : '$count asignaciones',
        child: Text(
          '$count',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.yellowField,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _AssignCourierButton extends StatelessWidget {
  const _AssignCourierButton({
    required this.label,
    required this.icon,
    this.compact = false,
    this.comfortable = false,
  });

  final String label;
  final IconData icon;
  final bool compact;
  final bool comfortable;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      height: compact ? (comfortable ? 36 : 32) : 44,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? (comfortable ? 15 : 13) : 20,
      ),
      decoration: AppTheme.buildActionDecoration(
        borderRadius: BorderRadius.circular(999),
        borderColor: AppTheme.strongBorder,
        boxShadow: const [],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppTheme.yellowField, size: compact ? 14 : 17),
          SizedBox(width: compact ? 4 : 7),
          Text(
            label,
            style:
                (compact && !comfortable
                        ? textTheme.labelSmall
                        : textTheme.labelMedium)
                    ?.copyWith(
                      color: AppTheme.yellowField,
                      fontWeight: FontWeight.w900,
                    ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _CourierAvatar extends StatelessWidget {
  const _CourierAvatar({
    required this.label,
    this.large = false,
    this.comfortable = false,
  });

  final String label;
  final bool large;
  final bool comfortable;

  @override
  Widget build(BuildContext context) {
    final size = large ? 88.0 : (comfortable ? 66.0 : 54.0);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.yellow,
            AppTheme.actionYellowStrong,
            AppTheme.orangeWarm,
          ],
        ),
        borderRadius: BorderRadius.circular(large ? 22 : 16),
      ),
      child: Text(
        label,
        style:
            (large
                    ? Theme.of(context).textTheme.headlineSmall
                    : comfortable
                    ? Theme.of(context).textTheme.headlineSmall
                    : Theme.of(context).textTheme.titleLarge)
                ?.copyWith(
                  color: AppTheme.blueDark,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  letterSpacing: 0,
                ),
      ),
    );
  }
}

class _CourierMetaChip extends StatelessWidget {
  const _CourierMetaChip({
    required this.icon,
    required this.label,
    this.emphasized = false,
    this.maxWidth,
  });

  final IconData icon;
  final String label;
  final bool emphasized;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = emphasized
        ? AppTheme.blueDark
        : AppTheme.yellowSurface;
    final foregroundColor = emphasized ? AppTheme.yellowField : AppTheme.blue;

    return Container(
      height: 30,
      constraints: maxWidth == null
          ? null
          : BoxConstraints(maxWidth: maxWidth!),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: emphasized ? AppTheme.blue : AppTheme.lightBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: foregroundColor),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: foregroundColor,
                fontWeight: FontWeight.w800,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
