import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:scan_agbc/nucleo/tema/app_theme.dart';
import 'package:scan_agbc/nucleo/utilidades/user_friendly_error_mapper.dart';
import 'package:scan_agbc/nucleo/componentes/app_cards.dart';
import 'package:scan_agbc/nucleo/componentes/app_feedback_banner.dart';
import 'package:scan_agbc/nucleo/componentes/app_page_scaffold.dart';
import 'package:scan_agbc/nucleo/componentes/app_view_mode_toggle.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/assigned_package_summary.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/package_tracking_result.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/repositorios/package_tracking_repository.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/utilidades/package_code_classifier.dart';
import 'package:scan_agbc/funcionalidades/seguimiento/presentacion/componentes/package_tracking_search_card.dart';
import 'assigned_package_detail_page.dart';

enum _SortOption { dateDesc, dateAsc }

extension _SortOptionX on _SortOption {
  String get label {
    switch (this) {
      case _SortOption.dateDesc:
        return 'Más recientes';
      case _SortOption.dateAsc:
        return 'Más antiguos';
    }
  }

  IconData get icon {
    switch (this) {
      case _SortOption.dateDesc:
        return Icons.arrow_downward_rounded;
      case _SortOption.dateAsc:
        return Icons.arrow_upward_rounded;
    }
  }
}

class AssignedPackagesPage extends StatefulWidget {
  const AssignedPackagesPage({
    super.key,
    required this.userId,
    required this.repository,
    this.courierName,
    this.initialAssignmentsFuture,
    this.allowStatusToggle = false,
    this.onScanCodeWithCamera,
  });

  final int userId;
  final PackageTrackingRepository repository;
  final String? courierName;
  final Future<List<AssignedPackageSummary>>? initialAssignmentsFuture;
  final bool allowStatusToggle;
  final Future<String?> Function()? onScanCodeWithCamera;

  @override
  State<AssignedPackagesPage> createState() => _AssignedPackagesPageState();
}

class _AssignedPackagesPageState extends State<AssignedPackagesPage> {
  static const int _maxVisibleAssignments = 200;

  late Future<List<AssignedPackageSummary>> _future =
      widget.initialAssignmentsFuture ?? _loadAssignments();
  _SortOption _currentSort = _SortOption.dateDesc;
  Set<PackageCategory> _activeFilters = {};
  bool _preferGridLayout = true;
  bool _searchingAssignedPackage = false;
  final TextEditingController _assignedSearchController =
      TextEditingController();
  final FocusNode _assignedSearchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _assignedSearchController.addListener(_onSearchTextChanged);
  }

  @override
  void dispose() {
    _assignedSearchController.removeListener(_onSearchTextChanged);
    _assignedSearchController.dispose();
    _assignedSearchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<List<AssignedPackageSummary>> _loadAssignments({
    bool forceRefresh = false,
  }) {
    return widget.repository.findAssignmentsForUser(
      widget.userId,
      forceRefresh: forceRefresh,
    );
  }

  Future<void> _reload() async {
    final nextFuture = _loadAssignments(forceRefresh: true);
    setState(() {
      _future = nextFuture;
    });
    await nextFuture;
  }

  List<AssignedPackageSummary> _applySortAndFilter(
    List<AssignedPackageSummary> assignments,
  ) {
    var result = List<AssignedPackageSummary>.of(assignments);

    final query = PackageCodeClassifier.normalize(
      _assignedSearchController.text,
    );
    if (query.isNotEmpty) {
      result = result.where((a) {
        final assignmentCode = PackageCodeClassifier.normalize(a.code);
        return assignmentCode.startsWith(query);
      }).toList();
    }

    if (_activeFilters.isNotEmpty) {
      result = result
          .where((a) => _activeFilters.contains(a.category))
          .toList();
    }

    result.sort((a, b) {
      switch (_currentSort) {
        case _SortOption.dateDesc:
          return _compareAssignmentsByActivity(a, b, newestFirst: true);
        case _SortOption.dateAsc:
          return _compareAssignmentsByActivity(a, b, newestFirst: false);
      }
    });

    return result.take(_maxVisibleAssignments).toList(growable: false);
  }

  int _compareAssignmentsByActivity(
    AssignedPackageSummary first,
    AssignedPackageSummary second, {
    required bool newestFirst,
  }) {
    final firstDate = first.createdAt;
    final secondDate = second.createdAt;

    if (firstDate != null && secondDate != null) {
      final dateComparison = newestFirst
          ? secondDate.compareTo(firstDate)
          : firstDate.compareTo(secondDate);
      if (dateComparison != 0) {
        return dateComparison;
      }
    } else if (firstDate != null) {
      return newestFirst ? -1 : 1;
    } else if (secondDate != null) {
      return newestFirst ? 1 : -1;
    }

    final statusComparison = _statusPriority(
      first.stateName,
    ).compareTo(_statusPriority(second.stateName));
    if (statusComparison != 0) {
      return statusComparison;
    }

    final categoryComparison = _categoryPriority(
      first.category,
    ).compareTo(_categoryPriority(second.category));
    if (categoryComparison != 0) {
      return categoryComparison;
    }

    final idComparison = newestFirst
        ? second.assignmentId.compareTo(first.assignmentId)
        : first.assignmentId.compareTo(second.assignmentId);
    if (idComparison != 0) {
      return idComparison;
    }

    return first.code.compareTo(second.code);
  }

  int _categoryPriority(PackageCategory category) {
    switch (category) {
      case PackageCategory.ems:
        return 0;
      case PackageCategory.certi:
        return 1;
      case PackageCategory.contrato:
        return 2;
      case PackageCategory.ordi:
        return 3;
    }
  }

  int _statusPriority(String rawStateName) {
    final normalized = rawStateName.trim().toUpperCase();
    if (normalized.contains('CARTERO') || normalized.contains('DOMICILIO')) {
      return 0;
    }
    if (normalized.contains('ASIGNADO')) {
      return 1;
    }
    return 2;
  }

  void _showFilterBottomSheet(List<AssignedPackageSummary> allAssignments) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _FilterBottomSheet(
          currentSort: _currentSort,
          activeFilters: _activeFilters,
          onApplyOptions: (newSort, newFilters) {
            setState(() {
              _currentSort = newSort;
              _activeFilters = newFilters;
            });
          },
        );
      },
    );
  }

  Future<void> _searchAssignedPackageFromText(
    List<AssignedPackageSummary> assignments,
  ) async {
    if (_searchingAssignedPackage) return;

    setState(() {
      _searchingAssignedPackage = true;
    });

    try {
      await _openAssignmentForCode(_assignedSearchController.text, assignments);
    } finally {
      if (mounted) {
        setState(() {
          _searchingAssignedPackage = false;
        });
      }
    }
  }

  Future<void> _scanAssignedPackage(
    List<AssignedPackageSummary> assignments,
  ) async {
    if (_searchingAssignedPackage) return;

    final scanCodeWithCamera = widget.onScanCodeWithCamera;
    if (scanCodeWithCamera == null) {
      showAppFeedbackBanner(
        context,
        'No se pudo abrir la cámara para buscar paquetes.',
        tone: AppFeedbackTone.error,
      );
      return;
    }

    setState(() {
      _searchingAssignedPackage = true;
    });

    try {
      final rawCode = await scanCodeWithCamera();
      if (!mounted || rawCode == null || rawCode.trim().isEmpty) return;

      final normalizedCode = PackageCodeClassifier.normalize(rawCode);
      if (normalizedCode.isNotEmpty) {
        _assignedSearchController.value = TextEditingValue(
          text: normalizedCode,
          selection: TextSelection.collapsed(offset: normalizedCode.length),
        );
      }

      await _openAssignmentForCode(rawCode, assignments);
    } finally {
      if (mounted) {
        setState(() {
          _searchingAssignedPackage = false;
        });
      }
    }
  }

  Future<void> _openAssignmentForCode(
    String rawCode,
    List<AssignedPackageSummary> currentAssignments,
  ) async {
    final validation = PackageCodeClassifier.validateForSearch(rawCode);
    final normalizedCode = validation.normalizedCode;
    if (!validation.isValid) {
      showAppFeedbackBanner(
        context,
        validation.errorMessage ?? 'Revisa el código e intenta nuevamente.',
        tone: AppFeedbackTone.error,
      );
      return;
    }

    final assignment = _findAssignmentByCode(
      currentAssignments,
      normalizedCode,
    );

    if (assignment == null) {
      showAppFeedbackBanner(
        context,
        'No encontramos $normalizedCode en tus asignaciones.',
        tone: AppFeedbackTone.error,
      );
      return;
    }

    await _openAssignmentDetail(assignment);
  }

  AssignedPackageSummary? _findAssignmentByCode(
    List<AssignedPackageSummary> assignments,
    String normalizedCode,
  ) {
    for (final assignment in assignments) {
      final assignmentCode = PackageCodeClassifier.normalize(assignment.code);
      if (assignmentCode == normalizedCode) {
        return assignment;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final normalizedCourierName = widget.courierName?.trim() ?? '';

    return AppPageScaffold(
      title: normalizedCourierName.isEmpty
          ? 'Asignaciones'
          : normalizedCourierName,
      resizeToAvoidBottomInset: false,
      floatingActionButton: FutureBuilder<List<AssignedPackageSummary>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done ||
              snapshot.hasError) {
            return const SizedBox.shrink();
          }
          final items = snapshot.data ?? const <AssignedPackageSummary>[];
          if (items.isEmpty) return const SizedBox.shrink();

          return FloatingActionButton.extended(
            onPressed: () => _showFilterBottomSheet(items),
            backgroundColor: AppTheme.blue,
            foregroundColor: AppTheme.yellowLight,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.filter_list_rounded),
                if (_activeFilters.isNotEmpty)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: AppTheme.errorRed,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            label: const Text(
              'Filtrar',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16.5),
            ),
          );
        },
      ),
      body: RefreshIndicator(
        color: AppTheme.blue,
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
              return _AssignmentListMessageState(
                title: 'No se pudieron cargar las asignaciones',
                message: _mapError(snapshot.error),
              );
            }

            final allAssignments =
                snapshot.data ?? const <AssignedPackageSummary>[];
            if (allAssignments.isEmpty) {
              return const _AssignmentListMessageState(
                title: 'Sin asignaciones',
                message: 'No hay paquetes asignados.',
              );
            }
            final assignments = _applySortAndFilter(allAssignments);
            final overviewStats = _AssignmentOverviewStats.fromAssignments(
              allAssignments,
            );

            return LayoutBuilder(
              builder: (context, constraints) {
                final canUseGrid = constraints.maxWidth >= 720;
                final useTwoColumns = canUseGrid && _preferGridLayout;

                return ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                  children: [
                    _AssignmentsOverviewCard(stats: overviewStats),
                    const SizedBox(height: 16),
                    PackageTrackingQuickSearchBar(
                      controller: _assignedSearchController,
                      focusNode: _assignedSearchFocusNode,
                      loading: _searchingAssignedPackage,
                      onSearch: () =>
                          _searchAssignedPackageFromText(allAssignments),
                      onScanWithCamera: widget.onScanCodeWithCamera == null
                          ? null
                          : () => _scanAssignedPackage(allAssignments),
                    ),
                    const SizedBox(height: 14),
                    if (canUseGrid) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: AppViewModeToggle(
                          gridEnabled: useTwoColumns,
                          onGridEnabledChanged: (enabled) {
                            setState(() => _preferGridLayout = enabled);
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (assignments.isEmpty)
                      const _AssignmentInlineMessageCard(
                        title: 'Sin resultados',
                        message:
                            'No hay paquetes con los filtros seleccionados.',
                      )
                    else if (useTwoColumns)
                      _AssignmentsGrid(
                        assignments: assignments,
                        onOpenAssignment: _openAssignmentDetail,
                      )
                    else
                      Column(
                        children: assignments
                            .map(
                              (assignment) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _AssignmentListTile(
                                  key: ValueKey(assignment.assignmentId),
                                  assignment: assignment,
                                  onTap: () =>
                                      _openAssignmentDetail(assignment),
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  String _mapError(Object? error) {
    return UserFriendlyErrorMapper.message(
      error,
      fallback: 'No pudimos cargar las asignaciones. Intenta nuevamente.',
    );
  }

  Future<void> _openAssignmentDetail(AssignedPackageSummary assignment) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AssignedPackageDetailPage(
          assignment: assignment,
          repository: widget.repository,
          userId: widget.userId,
        ),
      ),
    );
    if (updated == true && context.mounted) {
      await _reload();
    }
  }
}

class _AssignmentsGrid extends StatelessWidget {
  const _AssignmentsGrid({
    required this.assignments,
    required this.onOpenAssignment,
  });

  final List<AssignedPackageSummary> assignments;
  final ValueChanged<AssignedPackageSummary> onOpenAssignment;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: assignments.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: 138,
      ),
      itemBuilder: (context, index) {
        final assignment = assignments[index];
        return _AssignmentListTile(
          key: ValueKey(assignment.assignmentId),
          assignment: assignment,
          onTap: () => onOpenAssignment(assignment),
          compact: true,
        );
      },
    );
  }
}

class _FilterBottomSheet extends StatefulWidget {
  const _FilterBottomSheet({
    required this.currentSort,
    required this.activeFilters,
    required this.onApplyOptions,
  });

  final _SortOption currentSort;
  final Set<PackageCategory> activeFilters;
  final void Function(_SortOption, Set<PackageCategory>) onApplyOptions;

  @override
  State<_FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<_FilterBottomSheet> {
  late _SortOption _selectedSort;
  late Set<PackageCategory> _selectedFilters;

  final List<PackageCategory> _availableCategories = const [
    PackageCategory.ems,
    PackageCategory.certi,
    PackageCategory.contrato,
    PackageCategory.ordi,
  ];

  @override
  void initState() {
    super.initState();
    _selectedSort = widget.currentSort;
    _selectedFilters = Set.from(widget.activeFilters);
  }

  void _applyChanges() {
    widget.onApplyOptions(_selectedSort, _selectedFilters);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: const BoxDecoration(
        color: AppTheme.blue,
        borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 5,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: AppTheme.yellow.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const Text(
              'Ordenar por',
              style: TextStyle(
                color: AppTheme.yellow,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppTheme.blueDark,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0x33FFFFFF)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<_SortOption>(
                  value: _selectedSort,
                  isExpanded: true,
                  icon: const Icon(
                    Icons.expand_more_rounded,
                    color: AppTheme.yellow,
                  ),
                  dropdownColor: AppTheme.blueDark,
                  borderRadius: BorderRadius.circular(16),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                  items: _SortOption.values.map((option) {
                    return DropdownMenuItem<_SortOption>(
                      value: option,
                      child: Row(
                        children: [
                          Icon(option.icon, color: AppTheme.yellow, size: 20),
                          const SizedBox(width: 10),
                          Text(
                            option.label,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedSort = value);
                      _applyChanges();
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Filtrar Categorías',
              style: TextStyle(
                color: AppTheme.yellow,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _availableCategories.map((category) {
                final isSelected = _selectedFilters.contains(category);
                return FilterChip(
                  label: Text(category.label),
                  labelStyle: TextStyle(
                    color: isSelected ? AppTheme.blue : Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                  backgroundColor: AppTheme.blueDark,
                  selectedColor: AppTheme.yellow,
                  checkmarkColor: AppTheme.blue,
                  selected: isSelected,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isSelected
                          ? AppTheme.yellow
                          : AppTheme.yellow.withValues(alpha: 0.3),
                      width: 1.2,
                    ),
                  ),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedFilters.add(category);
                      } else {
                        _selectedFilters.remove(category);
                      }
                    });
                    _applyChanges();
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssignmentListTile extends StatelessWidget {
  const _AssignmentListTile({
    super.key,
    required this.assignment,
    required this.onTap,
    this.compact = false,
  });

  final AssignedPackageSummary assignment;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final statusStyle = _AssignmentStatusStyle.fromStateName(
      assignment.stateName,
    );
    final packageTypeStyle = _PackageTypeStyle.fromCategory(
      assignment.category,
    );
    const cardBackground = AppTheme.yellowField;
    const cardBorder = Color(0xFFDCAF31);
    const primaryTextColor = AppTheme.blueDark;
    const secondaryTextColor = AppTheme.blueDark;
    const chevronColor = AppTheme.blue;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 9 : 12,
            vertical: compact ? 9 : 12,
          ),
          decoration: BoxDecoration(
            color: cardBackground,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cardBorder, width: 1.8),
            boxShadow: [
              const BoxShadow(
                color: Color(0x221B305F),
                blurRadius: 18,
                offset: Offset(0, 9),
              ),
            ],
          ),
          child: Row(
            children: [
              SizedBox(
                width: compact ? 76 : 88,
                height: compact ? 76 : 88,
                child: Image.asset(
                  'assets/images/package_box.png',
                  fit: BoxFit.contain,
                ),
              ),
              SizedBox(width: compact ? 8 : 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      assignment.code,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: primaryTextColor,
                        fontWeight: FontWeight.w900,
                        fontSize: compact ? 16.4 : 18,
                        height: 1.05,
                        letterSpacing: 0.1,
                      ),
                    ),
                    SizedBox(height: compact ? 2 : 4),
                    Text(
                      'Paquete asignado',
                      style: TextStyle(
                        color: secondaryTextColor,
                        fontWeight: FontWeight.w700,
                        fontSize: compact ? 12.9 : 14,
                        height: 1.15,
                      ),
                    ),
                    SizedBox(height: compact ? 8 : 10),
                    Wrap(
                      spacing: compact ? 7 : 8,
                      runSpacing: compact ? 4 : 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _PackageTypeChip(
                          style: packageTypeStyle,
                          compact: compact,
                        ),
                        _AssignmentStatusChip(
                          style: statusStyle,
                          compact: compact,
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 7 : 8),
                    _AssignmentDateChip(
                      label: assignment.formattedDate,
                      compact: compact,
                    ),
                  ],
                ),
              ),
              SizedBox(width: compact ? 3 : 6),
              Icon(
                Icons.chevron_right_rounded,
                color: chevronColor,
                size: compact ? 20 : 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssignmentStatusChip extends StatelessWidget {
  const _AssignmentStatusChip({required this.style, this.compact = false});

  final _AssignmentStatusStyle style;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 10,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: style.backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: style.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 14, color: style.foregroundColor),
          const SizedBox(width: 5),
          Text(
            style.label,
            style: TextStyle(
              color: style.foregroundColor,
              fontWeight: FontWeight.w800,
              fontSize: compact ? 10.8 : 12.2,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _AssignmentStatusStyle {
  const _AssignmentStatusStyle({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderColor,
  });

  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;

  factory _AssignmentStatusStyle.fromStateName(String rawStateName) {
    final normalized = rawStateName.trim().toUpperCase();

    if (normalized.contains('DOMICILIO') || normalized.contains('CARTERO')) {
      return const _AssignmentStatusStyle(
        label: 'En progreso',
        icon: Icons.watch_later_outlined,
        backgroundColor: Color(0xFFE7EEF9),
        foregroundColor: AppTheme.blue,
        borderColor: Color(0xFF9BB4DA),
      );
    }

    if (normalized.contains('ASIGNADO')) {
      return const _AssignmentStatusStyle(
        label: 'Asignado',
        icon: Icons.schedule_rounded,
        backgroundColor: Color(0xFFF6D57F),
        foregroundColor: AppTheme.blueDark,
        borderColor: Color(0xFFD8B14F),
      );
    }

    if (normalized.contains('ENTREGADO')) {
      return const _AssignmentStatusStyle(
        label: 'Entregado',
        icon: Icons.check_circle_outline_rounded,
        backgroundColor: Color(0xFFDDF6E5),
        foregroundColor: AppTheme.successGreen,
        borderColor: Color(0xFF87D4A1),
      );
    }

    return _AssignmentStatusStyle(
      label: rawStateName.trim().isEmpty ? 'Asignado' : rawStateName.trim(),
      icon: Icons.local_shipping_outlined,
      backgroundColor: const Color(0xFFE7EEF9),
      foregroundColor: AppTheme.blueDark,
      borderColor: const Color(0xFF9BB4DA),
    );
  }
}

class _PackageTypeChip extends StatelessWidget {
  const _PackageTypeChip({required this.style, this.compact = false});

  final _PackageTypeStyle style;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 10,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: style.backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: style.borderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x160F1E3D),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_shipping_rounded,
            size: 14,
            color: style.foregroundColor,
          ),
          const SizedBox(width: 5),
          Text(
            style.label,
            style: TextStyle(
              color: style.foregroundColor,
              fontWeight: FontWeight.w800,
              fontSize: compact ? 10.8 : 12,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _AssignmentDateChip extends StatelessWidget {
  const _AssignmentDateChip({required this.label, this.compact = false});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: AppTheme.yellowLight,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x80C9B58B)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.calendar_today_rounded,
            size: 13,
            color: AppTheme.blueMid,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: AppTheme.blueMid,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 10.6 : 11.8,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _PackageTypeStyle {
  const _PackageTypeStyle({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderColor,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;

  factory _PackageTypeStyle.fromCategory(PackageCategory category) {
    switch (category) {
      case PackageCategory.ems:
        return const _PackageTypeStyle(
          label: 'EMS',
          backgroundColor: AppTheme.blue,
          foregroundColor: Colors.white,
          borderColor: AppTheme.blueDark,
        );
      case PackageCategory.certi:
        return const _PackageTypeStyle(
          label: 'Certificado',
          backgroundColor: AppTheme.confirmBlue,
          foregroundColor: Colors.white,
          borderColor: AppTheme.confirmBlueDark,
        );
      case PackageCategory.contrato:
        return const _PackageTypeStyle(
          label: 'Contrato',
          backgroundColor: AppTheme.orangeWarm,
          foregroundColor: AppTheme.blueDark,
          borderColor: Color(0xFFE1A73A),
        );
      case PackageCategory.ordi:
        return const _PackageTypeStyle(
          label: 'Ordinario',
          backgroundColor: AppTheme.yellow,
          foregroundColor: AppTheme.blueDark,
          borderColor: Color(0xFFD8A722),
        );
    }
  }
}

class _AssignmentOverviewStats {
  const _AssignmentOverviewStats({required this.entries});

  final List<_AssignmentOverviewEntry> entries;

  int get total => entries.fold(0, (sum, entry) => sum + entry.count);

  _AssignmentOverviewEntry entryFor(PackageCategory category) {
    return entries.firstWhere((entry) => entry.category == category);
  }

  factory _AssignmentOverviewStats.fromAssignments(
    List<AssignedPackageSummary> assignments,
  ) {
    const categories = [
      PackageCategory.ems,
      PackageCategory.certi,
      PackageCategory.contrato,
      PackageCategory.ordi,
    ];

    return _AssignmentOverviewStats(
      entries: categories.map((category) {
        final count = assignments
            .where((item) => item.category == category)
            .length;
        return _AssignmentOverviewEntry(category: category, count: count);
      }).toList(),
    );
  }
}

class _AssignmentOverviewEntry {
  const _AssignmentOverviewEntry({required this.category, required this.count});

  final PackageCategory category;
  final int count;

  _PackageTypeStyle get style => _PackageTypeStyle.fromCategory(category);

  String get summaryLabel {
    switch (category) {
      case PackageCategory.ems:
        return 'EMS';
      case PackageCategory.certi:
        return 'Certificados';
      case PackageCategory.contrato:
        return 'Contratos';
      case PackageCategory.ordi:
        return 'Ordinarios';
    }
  }

  Color get summaryAccentColor {
    switch (category) {
      case PackageCategory.ems:
        return AppTheme.blue;
      case PackageCategory.certi:
        return AppTheme.blueMid;
      case PackageCategory.contrato:
        return AppTheme.orangeWarm;
      case PackageCategory.ordi:
        return AppTheme.yellow;
    }
  }
}

class _AssignmentsOverviewCard extends StatelessWidget {
  const _AssignmentsOverviewCard({required this.stats});

  final _AssignmentOverviewStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          'Asignaciones',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.blueDark,
            fontWeight: FontWeight.w900,
            fontSize: 22,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AssignmentsOverviewLegendItem(
                    entry: stats.entryFor(PackageCategory.ems),
                  ),
                  const SizedBox(height: 22),
                  _AssignmentsOverviewLegendItem(
                    entry: stats.entryFor(PackageCategory.contrato),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _AssignmentsDonutChart(stats: stats),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _AssignmentsOverviewLegendItem(
                    entry: stats.entryFor(PackageCategory.certi),
                    rightAligned: true,
                  ),
                  const SizedBox(height: 22),
                  _AssignmentsOverviewLegendItem(
                    entry: stats.entryFor(PackageCategory.ordi),
                    rightAligned: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AssignmentsOverviewLegendItem extends StatelessWidget {
  const _AssignmentsOverviewLegendItem({
    required this.entry,
    this.rightAligned = false,
  });

  final _AssignmentOverviewEntry entry;
  final bool rightAligned;

  @override
  Widget build(BuildContext context) {
    final opacity = entry.count == 0 ? 0.45 : 1.0;

    return Opacity(
      opacity: opacity,
      child: Align(
        alignment: rightAligned ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: rightAligned
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              entry.summaryLabel,
              textAlign: rightAligned ? TextAlign.right : TextAlign.left,
              style: const TextStyle(
                color: AppTheme.blueDark,
                fontWeight: FontWeight.w800,
                fontSize: 15,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${entry.count}',
              textAlign: rightAligned ? TextAlign.right : TextAlign.left,
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w900,
                fontSize: 24,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssignmentsDonutChart extends StatelessWidget {
  const _AssignmentsDonutChart({required this.stats});

  final _AssignmentOverviewStats stats;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 156,
      height: 156,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size.square(156),
            painter: _AssignmentsDonutPainter(stats: stats),
          ),
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: AppTheme.blueDark,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppTheme.yellow.withValues(alpha: 0.18),
                width: 2.4,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x120F1E3D),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              '${stats.total}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.yellow,
                fontWeight: FontWeight.w900,
                fontSize: 31,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssignmentsDonutPainter extends CustomPainter {
  const _AssignmentsDonutPainter({required this.stats});

  final _AssignmentOverviewStats stats;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = 30.0;
    final radius = (size.shortestSide - strokeWidth) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = AppTheme.yellowSurface;

    canvas.drawCircle(center, radius, trackPaint);

    final activeEntries = stats.entries
        .where((entry) => entry.count > 0)
        .toList();
    if (stats.total == 0 || activeEntries.isEmpty) {
      return;
    }

    final rect = Rect.fromCircle(center: center, radius: radius);
    final segmentPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    var cursor = -math.pi / 2;
    for (final entry in activeEntries) {
      final sweep = (entry.count / stats.total) * (math.pi * 2);
      final gap = activeEntries.length == 1
          ? 0.0
          : math.min(0.12, sweep * 0.18);
      final startAngle = cursor + (gap / 2);
      final adjustedSweep = math.max(0.0, sweep - gap);
      if (adjustedSweep > 0) {
        canvas.drawArc(
          rect,
          startAngle,
          adjustedSweep,
          false,
          segmentPaint..color = entry.summaryAccentColor,
        );
      }
      cursor += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _AssignmentsDonutPainter oldDelegate) {
    return oldDelegate.stats.entries != stats.entries;
  }
}

class _AssignmentListMessageState extends StatelessWidget {
  const _AssignmentListMessageState({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [_AssignmentInlineMessageCard(title: title, message: message)],
    );
  }
}

class _AssignmentInlineMessageCard extends StatelessWidget {
  const _AssignmentInlineMessageCard({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return AppStatusMessageCard(
      title: title,
      message: message,
      icon: Icons.inbox_rounded,
    );
  }
}
