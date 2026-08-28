import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:scan_agbc/nucleo/tema/app_theme.dart';
import 'package:scan_agbc/nucleo/utilidades/user_friendly_error_mapper.dart';
import 'package:scan_agbc/nucleo/componentes/app_cards.dart';
import 'package:scan_agbc/nucleo/componentes/app_feedback_banner.dart';
import 'package:scan_agbc/nucleo/componentes/app_page_scaffold.dart';
import 'package:scan_agbc/nucleo/componentes/app_view_mode_toggle.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/courier_inventory_packages_result.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/courier_summary.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/inventory_package_summary.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/package_tracking_result.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/repositorios/package_tracking_repository.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/utilidades/package_code_classifier.dart';
import 'package:scan_agbc/funcionalidades/seguimiento/presentacion/paginas/package_tracking_search_page.dart';
import 'package:scan_agbc/funcionalidades/cartero/presentacion/componentes/package_max_attempts_alert.dart';
import 'package:scan_agbc/funcionalidades/seguimiento/presentacion/componentes/package_tracking_search_card.dart';

enum _InventorySortOption { newest, oldest }

class _DragSelectionTarget {
  const _DragSelectionTarget({required this.packageKey, required this.bounds});

  final String packageKey;
  final Rect bounds;
}

extension _InventorySortOptionX on _InventorySortOption {
  String get label {
    switch (this) {
      case _InventorySortOption.newest:
        return 'Más recientes';
      case _InventorySortOption.oldest:
        return 'Más antiguos';
    }
  }

  IconData get icon {
    switch (this) {
      case _InventorySortOption.newest:
        return Icons.arrow_downward_rounded;
      case _InventorySortOption.oldest:
        return Icons.arrow_upward_rounded;
    }
  }
}

class CourierInventoryAssignmentPage extends StatefulWidget {
  const CourierInventoryAssignmentPage({
    super.key,
    required this.courier,
    required this.repository,
    this.onScanCodeWithCamera,
    this.onScanCodesWithCamera,
    this.initialPackagesFuture,
  });

  final CourierSummary courier;
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
  final Future<CourierInventoryPackagesResult>? initialPackagesFuture;

  @override
  State<CourierInventoryAssignmentPage> createState() =>
      _CourierInventoryAssignmentPageState();
}

class _CourierInventoryAssignmentPageState
    extends State<CourierInventoryAssignmentPage> {
  static const int _pageSize = 10;

  // Persists selected package keys per courier across page visits.
  static final Map<int, Set<String>> _selectionCache = <int, Set<String>>{};

  late Future<CourierInventoryPackagesResult> _future =
      widget.initialPackagesFuture ?? _loadPackages();
  bool _bulkAssigning = false;
  _InventorySortOption _currentSort = _InventorySortOption.newest;
  Set<PackageCategory> _activeFilters = <PackageCategory>{};
  Set<String> _activeStateFilters = <String>{};
  late final ValueNotifier<Set<String>> _selectedPackageKeysNotifier =
      ValueNotifier<Set<String>>(
        Set<String>.of(_selectionCache[widget.courier.id] ?? const <String>{}),
      );
  final Map<String, GlobalKey> _packageCardKeys = <String, GlobalKey>{};
  bool _preferGridLayout = true;
  bool _searchingPackage = false;
  bool _selectionDragActive = false;
  String? _lastDragSelectedPackageKey;
  List<_DragSelectionTarget> _dragSelectionTargets =
      const <_DragSelectionTarget>[];
  int _currentPage = 0;
  List<InventoryPackageSummary>? _filteredPackagesCacheSource;
  String? _filteredPackagesCacheQuery;
  Set<PackageCategory>? _filteredPackagesCacheCategories;
  Set<String>? _filteredPackagesCacheStates;
  _InventorySortOption? _filteredPackagesCacheSort;
  List<InventoryPackageSummary>? _filteredPackagesCacheValue;
  final TextEditingController _packageSearchController =
      TextEditingController();
  final FocusNode _packageSearchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _packageSearchController.addListener(_onPackageSearchChanged);
    _selectedPackageKeysNotifier.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    _packageSearchController.removeListener(_onPackageSearchChanged);
    _selectedPackageKeysNotifier.removeListener(_onSelectionChanged);
    _selectedPackageKeysNotifier.dispose();
    _packageSearchController.dispose();
    _packageSearchFocusNode.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    final current = _selectedPackageKeysNotifier.value;
    if (current.isEmpty) {
      _selectionCache.remove(widget.courier.id);
    } else {
      _selectionCache[widget.courier.id] = Set<String>.of(current);
    }
  }

  void _onPackageSearchChanged() {
    if (mounted) {
      setState(() {
        _currentPage = 0;
      });
    }
  }

  Future<CourierInventoryPackagesResult> _loadPackages({
    bool forceRefresh = false,
  }) {
    return widget.repository.findInventoryPackagesForCourier(
      widget.courier.id,
      forceRefresh: forceRefresh,
    );
  }

  Future<void> _reload() async {
    final nextFuture = _loadPackages(forceRefresh: true);
    _selectedPackageKeysNotifier.value = <String>{};
    _selectionCache.remove(widget.courier.id);
    setState(() {
      _future = nextFuture;
      _currentPage = 0;
    });
    await nextFuture;
  }

  Widget _buildInitialLoadingView() {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          sliver: SliverToBoxAdapter(
            child: _CourierInventoryHeaderCard(
              courier: widget.courier,
              city: widget.courier.city.trim().isEmpty
                  ? 'Sin ciudad'
                  : widget.courier.city.trim().toUpperCase(),
              availablePackagesCount: 0,
              visiblePackagesCount: 0,
              hasActiveFilters: false,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          sliver: SliverToBoxAdapter(
            child: AppPanelCard(
              borderRadius: AppTheme.radiusXLarge,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 22,
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.6,
                        color: AppTheme.blue,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Cargando paquetes...',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppTheme.blueDark,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openPackageDetails(InventoryPackageSummary package) async {
    final initialLookupFuture = widget.repository.findByCode(package.code);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PackageTrackingSearchPage(
          repository: widget.repository,
          initialCode: package.code,
          initialLookupFuture: initialLookupFuture,
          assignmentTargetName: widget.courier.displayName,
        ),
      ),
    );
  }

  Future<void> _openPackageDetailsReadOnly(
    InventoryPackageSummary package, {
    BuildContext? navigatorContext,
  }) async {
    final initialLookupFuture = widget.repository.findByCode(package.code);
    await Navigator.of(navigatorContext ?? context).push<void>(
      MaterialPageRoute(
        builder: (_) => PackageTrackingSearchPage(
          repository: widget.repository,
          initialCode: package.code,
          initialLookupFuture: initialLookupFuture,
        ),
      ),
    );
  }

  Future<void> _searchPackageFromText(
    List<InventoryPackageSummary> packages,
  ) async {
    if (_searchingPackage) return;

    setState(() {
      _searchingPackage = true;
    });

    try {
      await _openPackageForCode(_packageSearchController.text, packages);
    } finally {
      if (mounted) {
        setState(() {
          _searchingPackage = false;
        });
      }
    }
  }

  Future<void> _scanPackageForAssignment(
    List<InventoryPackageSummary> packages,
  ) async {
    if (_searchingPackage) return;

    final scanCodesWithCamera = widget.onScanCodesWithCamera;
    final scanCodeWithCamera = widget.onScanCodeWithCamera;
    if (scanCodesWithCamera == null && scanCodeWithCamera == null) {
      showAppFeedbackBanner(
        context,
        'No se pudo abrir la cámara para buscar paquetes.',
        tone: AppFeedbackTone.error,
      );
      return;
    }

    setState(() {
      _searchingPackage = true;
    });

    try {
      List<String>? rawCodes;
      if (scanCodesWithCamera != null) {
        final availableCodes = packages
            .where(_canAssignPackage)
            .map((package) => PackageCodeClassifier.normalize(package.code))
            .where((code) => code.isNotEmpty)
            .toSet();
        final initiallySelectedCodes = _selectedPackagesFrom(packages)
            .map((package) => PackageCodeClassifier.normalize(package.code))
            .where((code) => code.isNotEmpty)
            .toSet();
        rawCodes = await scanCodesWithCamera(
          availableCodes,
          initiallySelectedCodes,
          (selectedCodes) =>
              _syncScannedPackageSelection(selectedCodes, packages),
          (selectedCodes) => _reviewScannedPackages(selectedCodes, packages),
        );
        if (!mounted) return;
        if (rawCodes != null) {
          _syncScannedPackageSelection(rawCodes.toSet(), packages);
        }
        _packageSearchController.clear();
        return;
      } else {
        final rawCode = await scanCodeWithCamera!();
        rawCodes = rawCode == null ? null : <String>[rawCode];
      }
      if (!mounted || rawCodes == null || rawCodes.isEmpty) return;

      final nextSelectedKeys = Set<String>.of(
        _selectedPackageKeysNotifier.value,
      );
      var addedCount = 0;
      var skippedCount = 0;

      for (final rawCode in rawCodes) {
        final validation = PackageCodeClassifier.validateForSearch(rawCode);
        if (!validation.isValid || validation.normalizedCode.isEmpty) {
          skippedCount += 1;
          continue;
        }

        final package = _findPackageByCode(packages, validation.normalizedCode);
        if (package == null || !_canAssignPackage(package)) {
          skippedCount += 1;
          continue;
        }

        if (nextSelectedKeys.add(_packageKey(package))) {
          addedCount += 1;
        } else {
          skippedCount += 1;
        }
      }

      _selectedPackageKeysNotifier.value = nextSelectedKeys;
      _packageSearchController.clear();

      if (addedCount > 0) {
        showAppFeedbackBanner(
          context,
          addedCount == 1
              ? 'Paquete agregado a la lista de asignación.'
              : '$addedCount paquetes agregados a la lista de asignación.',
          tone: AppFeedbackTone.success,
        );
      }
      if (skippedCount > 0) {
        showAppFeedbackBanner(
          context,
          skippedCount == 1
              ? 'Un paquete ya estaba seleccionado o no está disponible.'
              : '$skippedCount paquetes ya estaban seleccionados o no estan disponibles.',
          tone: AppFeedbackTone.info,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _searchingPackage = false;
        });
      }
    }
  }

  void _syncScannedPackageSelection(
    Set<String> selectedCodes,
    List<InventoryPackageSummary> packages,
  ) {
    if (!mounted) return;
    final normalizedCodes = selectedCodes
        .map(PackageCodeClassifier.normalize)
        .where((code) => code.isNotEmpty)
        .toSet();
    _selectedPackageKeysNotifier.value = packages
        .where(
          (package) => normalizedCodes.contains(
            PackageCodeClassifier.normalize(package.code),
          ),
        )
        .map(_packageKey)
        .toSet();
  }

  Future<List<String>?> _reviewScannedPackages(
    List<String> selectedCodes,
    List<InventoryPackageSummary> packages,
  ) async {
    final selectedCodeSet = selectedCodes
        .map(PackageCodeClassifier.normalize)
        .where((code) => code.isNotEmpty)
        .toSet();
    final selectedPackages = packages
        .where(
          (package) => selectedCodeSet.contains(
            PackageCodeClassifier.normalize(package.code),
          ),
        )
        .toList(growable: false);
    if (selectedPackages.isEmpty) return selectedCodes;

    final reviewedPackages = await _showSelectedPackagesPreview(
      selectedPackages,
      syncSelection: false,
      confirmButtonLabel: 'Volver a la cámara',
      description:
          'Revisa los paquetes detectados. Puedes quitar cualquiera antes de continuar.',
    );
    if (reviewedPackages == null) return selectedCodes;

    return reviewedPackages
        .map((package) => PackageCodeClassifier.normalize(package.code))
        .toList(growable: false);
  }

  Future<void> _openPackageForCode(
    String rawCode,
    List<InventoryPackageSummary> packages,
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

    var package = _findPackageByCode(packages, normalizedCode);
    if (package == null) {
      setState(() {
        _searchingPackage = true;
      });
      try {
        final result = await widget.repository.findByCode(normalizedCode);
        if (!mounted) return;

        if (result == null) {
          showAppFeedbackBanner(
            context,
            'No encontramos $normalizedCode en los paquetes de este inventario.',
            tone: AppFeedbackTone.error,
          );
          return;
        }

        final courierCity = widget.courier.city.trim().toUpperCase();
        final packageCity = result.city.trim().toUpperCase();
        if (courierCity != packageCity) {
          showAppFeedbackBanner(
            context,
            'Este paquete no está disponible para la región. Revisa.',
            tone: AppFeedbackTone.error,
          );
          return;
        }

        if (result.packageId <= 0) {
          showAppFeedbackBanner(
            context,
            'No se pudo determinar el identificador del paquete $normalizedCode.',
            tone: AppFeedbackTone.error,
          );
          return;
        }

        final stateName = result.safeStateName.toUpperCase();
        final isContractOrEms =
            result.category == PackageCategory.contrato ||
            result.category == PackageCategory.ems;
        final isAssignableState = isContractOrEms
            ? (stateName == 'ALMACEN' ||
                  stateName == 'RECIBIDO' ||
                  stateName == 'DEVOLUCION')
            : (stateName == 'VENTANILLA' || stateName == 'DEVOLUCION');

        if (!isAssignableState) {
          showAppFeedbackBanner(
            context,
            'El paquete $normalizedCode no está disponible para asignar (estado: $stateName).',
            tone: AppFeedbackTone.error,
          );
          return;
        }

        package = InventoryPackageSummary(
          packageId: result.packageId,
          packageType: result.category,
          code: result.code,
          recipientName: result.recipientName,
          city: result.city,
          createdAt: null,
          stateName: result.stateName,
          attemptCount: result.attemptCount,
        );
      } catch (error) {
        if (!mounted) return;
        showAppFeedbackBanner(
          context,
          'No pudimos buscar este paquete. Intenta nuevamente.',
          tone: AppFeedbackTone.error,
        );
        return;
      } finally {
        if (mounted) {
          setState(() {
            _searchingPackage = false;
          });
        }
      }
    }

    await _openPackageDetails(package);
  }

  InventoryPackageSummary? _findPackageByCode(
    List<InventoryPackageSummary> packages,
    String normalizedCode,
  ) {
    for (final package in packages) {
      final packageCode = PackageCodeClassifier.normalize(package.code);
      if (packageCode == normalizedCode) {
        return package;
      }
    }
    return null;
  }

  String _mapError(Object error) {
    return UserFriendlyErrorMapper.message(
      error,
      fallback:
          'No pudimos completar la asignación en este momento. Intenta nuevamente.',
    );
  }

  bool _isPackageAvailabilityError(Object error) {
    final normalized = error.toString().toLowerCase();
    return normalized.contains('package_not_available') ||
        normalized.contains('ya no esta disponible para asignar') ||
        normalized.contains('ya no está disponible para asignar') ||
        normalized.contains('cambió de estado') ||
        normalized.contains('cambio de estado');
  }

  String _packageKey(InventoryPackageSummary package) {
    return '${package.packageType.name}:${package.packageId}';
  }

  GlobalKey _cardKeyFor(InventoryPackageSummary package) {
    return _packageCardKeys.putIfAbsent(_packageKey(package), GlobalKey.new);
  }

  void _togglePackageSelection(InventoryPackageSummary package) {
    final packageKey = _packageKey(package);
    final nextKeys = Set<String>.of(_selectedPackageKeysNotifier.value);
    if (nextKeys.contains(packageKey)) {
      nextKeys.remove(packageKey);
    } else {
      nextKeys.add(packageKey);
    }
    _selectedPackageKeysNotifier.value = nextKeys;
  }

  void _handlePackageCardTap(InventoryPackageSummary package) {
    if (_selectedPackageKeysNotifier.value.isNotEmpty) {
      _togglePackageSelection(package);
      return;
    }

    _openPackageDetailsReadOnly(package);
  }

  void _startDragSelection(
    InventoryPackageSummary package,
    List<InventoryPackageSummary> visiblePackages,
  ) {
    HapticFeedback.selectionClick();
    final packageKey = _packageKey(package);
    _prepareDragSelectionTargets(visiblePackages);
    final nextKeys = Set<String>.of(_selectedPackageKeysNotifier.value)
      ..add(packageKey);
    _selectionDragActive = true;
    _lastDragSelectedPackageKey = packageKey;
    _selectedPackageKeysNotifier.value = nextKeys;
  }

  void _prepareDragSelectionTargets(List<InventoryPackageSummary> packages) {
    final targets = <_DragSelectionTarget>[];

    for (final package in packages) {
      final packageKey = _packageKey(package);
      final key = _packageCardKeys[packageKey];
      final context = key?.currentContext;
      if (context == null) continue;

      final renderObject = context.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) continue;

      final topLeft = renderObject.localToGlobal(Offset.zero);
      targets.add(
        _DragSelectionTarget(
          packageKey: packageKey,
          bounds: topLeft & renderObject.size,
        ),
      );
    }

    _dragSelectionTargets = targets;
  }

  void _updateDragSelection(Offset globalPosition) {
    if (!_selectionDragActive) return;

    for (final target in _dragSelectionTargets) {
      if (!target.bounds.contains(globalPosition)) continue;

      final packageKey = target.packageKey;
      if (_lastDragSelectedPackageKey == packageKey ||
          _selectedPackageKeysNotifier.value.contains(packageKey)) {
        return;
      }

      HapticFeedback.selectionClick();
      _lastDragSelectedPackageKey = packageKey;
      _selectedPackageKeysNotifier.value = {
        ..._selectedPackageKeysNotifier.value,
        packageKey,
      };
      return;
    }
  }

  void _endDragSelection() {
    if (!_selectionDragActive) return;
    _selectionDragActive = false;
    _lastDragSelectedPackageKey = null;
    _dragSelectionTargets = const <_DragSelectionTarget>[];
  }

  void _clearCurrentPageSelection(List<InventoryPackageSummary> packages) {
    final pageKeys = packages.map(_packageKey).toSet();
    final nextKeys = Set<String>.of(_selectedPackageKeysNotifier.value)
      ..removeWhere(pageKeys.contains);
    _selectedPackageKeysNotifier.value = nextKeys;
  }

  void _selectCurrentPage(List<InventoryPackageSummary> packages) {
    _selectedPackageKeysNotifier.value = {
      ..._selectedPackageKeysNotifier.value,
      ...packages.map(_packageKey),
    };
  }

  List<InventoryPackageSummary> _filteredPackages(
    List<InventoryPackageSummary> packages,
  ) {
    final query = PackageCodeClassifier.normalize(
      _packageSearchController.text,
    );
    final cachedValue = _filteredPackagesCacheValue;
    if (cachedValue != null &&
        identical(_filteredPackagesCacheSource, packages) &&
        _filteredPackagesCacheQuery == query &&
        _filteredPackagesCacheSort == _currentSort &&
        _setEquals(_filteredPackagesCacheCategories, _activeFilters) &&
        _setEquals(_filteredPackagesCacheStates, _activeStateFilters)) {
      return cachedValue;
    }

    final hasQuery = query.isNotEmpty;
    final hasCategoryFilters = _activeFilters.isNotEmpty;
    final hasStateFilters = _activeStateFilters.isNotEmpty;
    final result = <InventoryPackageSummary>[];

    for (final item in packages) {
      if (hasQuery) {
        final packageCode = PackageCodeClassifier.normalize(item.code);
        if (!packageCode.startsWith(query)) continue;
      }
      if (hasCategoryFilters && !_activeFilters.contains(item.packageType)) {
        continue;
      }
      if (hasStateFilters &&
          !_activeStateFilters.contains(item.safeStateName)) {
        continue;
      }
      result.add(item);
    }

    result.sort((first, second) {
      switch (_currentSort) {
        case _InventorySortOption.newest:
          return _comparePackagesByActivity(first, second, newestFirst: true);
        case _InventorySortOption.oldest:
          return _comparePackagesByActivity(first, second, newestFirst: false);
      }
    });

    _filteredPackagesCacheSource = packages;
    _filteredPackagesCacheQuery = query;
    _filteredPackagesCacheCategories = Set<PackageCategory>.of(_activeFilters);
    _filteredPackagesCacheStates = Set<String>.of(_activeStateFilters);
    _filteredPackagesCacheSort = _currentSort;
    _filteredPackagesCacheValue = result;
    return result;
  }

  bool _setEquals<T>(Set<T>? first, Set<T> second) {
    if (first == null || first.length != second.length) return false;
    for (final item in first) {
      if (!second.contains(item)) return false;
    }
    return true;
  }

  int _totalPagesFor(List<InventoryPackageSummary> packages) {
    if (packages.isEmpty) {
      return 0;
    }

    return (packages.length / _pageSize).ceil();
  }

  int _effectivePageIndex(List<InventoryPackageSummary> packages) {
    final totalPages = _totalPagesFor(packages);
    if (totalPages == 0) {
      return 0;
    }

    return math.min(_currentPage, totalPages - 1);
  }

  List<InventoryPackageSummary> _packagesForCurrentPage(
    List<InventoryPackageSummary> packages,
  ) {
    if (packages.isEmpty) {
      return const <InventoryPackageSummary>[];
    }

    final pageIndex = _effectivePageIndex(packages);
    final start = pageIndex * _pageSize;
    final end = math.min(start + _pageSize, packages.length);
    return packages.sublist(start, end);
  }

  List<InventoryPackageSummary> _selectedPackagesFrom(
    List<InventoryPackageSummary> packages,
  ) {
    return packages
        .where(
          (package) =>
              _selectedPackageKeysNotifier.value.contains(_packageKey(package)),
        )
        .toList(growable: false);
  }

  Future<void> _assignSelectedPackages(
    List<InventoryPackageSummary> packages,
  ) async {
    if (_bulkAssigning) return;

    final selectedPackages = _selectedPackagesFrom(packages);
    if (selectedPackages.isEmpty) {
      showAppFeedbackBanner(
        context,
        'Selecciona al menos un paquete para asignar.',
        tone: AppFeedbackTone.error,
      );
      return;
    }

    final blockedPackages = selectedPackages
        .where((package) => !_canAssignPackage(package))
        .toList(growable: false);
    if (blockedPackages.isNotEmpty) {
      showAppFeedbackBanner(
        context,
        'Hay paquetes seleccionados que ya no se pueden asignar.',
        tone: AppFeedbackTone.error,
      );
      return;
    }

    final packagesWithMaxAttempts = selectedPackages
        .where((package) => package.hasMaximumAttempts)
        .toList(growable: false);
    if (packagesWithMaxAttempts.isNotEmpty) {
      await showPackageMaxAttemptsAlert(context);
      if (!mounted) return;
    }

    final confirmedPackages = await _showSelectedPackagesPreview(
      selectedPackages,
    );
    if (confirmedPackages == null || confirmedPackages.isEmpty || !mounted) {
      return;
    }

    setState(() {
      _bulkAssigning = true;
    });

    try {
      final packagesByType = <PackageCategory, List<InventoryPackageSummary>>{};
      for (final package in confirmedPackages) {
        packagesByType.putIfAbsent(package.packageType, () => []).add(package);
      }

      for (final entry in packagesByType.entries) {
        await widget.repository.assignInventoryPackages(
          courierUserId: widget.courier.id,
          packageType: entry.key,
          packageIds: entry.value
              .map((package) => package.packageId)
              .toList(growable: false),
        );
      }

      if (!mounted) return;
      showAppFeedbackBanner(
        context,
        confirmedPackages.length == 1
            ? 'Paquete asignado correctamente.'
            : '${confirmedPackages.length} paquetes asignados correctamente.',
        tone: AppFeedbackTone.success,
      );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      final message = _mapError(error);
      if (_isPackageAvailabilityError(error)) {
        try {
          await _reload();
        } catch (_) {
          // El error original de asignación es más útil para el usuario.
        }
        if (!mounted) return;
      }
      showAppFeedbackBanner(context, message, tone: AppFeedbackTone.error);
    } finally {
      if (mounted) {
        setState(() {
          _bulkAssigning = false;
        });
      }
    }
  }

  Future<List<InventoryPackageSummary>?> _showSelectedPackagesPreview(
    List<InventoryPackageSummary> selectedPackages, {
    bool syncSelection = true,
    String confirmButtonLabel = 'Confirmar',
    String? description,
  }) async {
    final sortedPackages = List<InventoryPackageSummary>.of(selectedPackages)
      ..sort(
        (first, second) =>
            _comparePackagesByActivity(first, second, newestFirst: true),
      );

    return showModalBottomSheet<List<InventoryPackageSummary>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (dialogContext) {
        var previewPackages = sortedPackages;

        void removePreviewPackages(
          void Function(List<InventoryPackageSummary> nextPackages) apply,
        ) {
          final nextPackages = List<InventoryPackageSummary>.of(
            previewPackages,
          );
          apply(nextPackages);
          if (syncSelection) {
            final nextKeys = nextPackages.map(_packageKey).toSet();
            _selectedPackageKeysNotifier.value = _selectedPackageKeysNotifier
                .value
                .where(nextKeys.contains)
                .toSet();
          }
          previewPackages = nextPackages;
        }

        void closeIfEmpty() {
          if (previewPackages.isEmpty) {
            Navigator.of(
              dialogContext,
            ).pop(syncSelection ? null : const <InventoryPackageSummary>[]);
          }
        }

        return SafeArea(
          top: false,
          child: FractionallySizedBox(
            heightFactor: 0.82,
            child: StatefulBuilder(
              builder: (context, setPreviewState) {
                return Container(
                  decoration: const BoxDecoration(
                    color: AppTheme.yellowField,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(30),
                    ),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      Container(
                        width: 54,
                        height: 5,
                        decoration: BoxDecoration(
                          color: AppTheme.blue.withValues(alpha: 0.24),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              previewPackages.length == 1
                                  ? 'Confirmar paquete'
                                  : 'Confirmar ${previewPackages.length} paquetes',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: AppTheme.blueDark,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              description ??
                                  'Revisa la seleccion antes de asignarla a ${widget.courier.displayName.toUpperCase()}.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: AppTheme.blueMid,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 14),
                            _BatchPreviewActions(
                              totalItems: previewPackages.length,
                              onClearAll: () {
                                setPreviewState(() {
                                  removePreviewPackages(
                                    (nextPackages) => nextPackages.clear(),
                                  );
                                });
                                closeIfEmpty();
                              },
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                          itemCount: previewPackages.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final package = previewPackages[index];
                            return _SelectedPackagePreviewTile(
                              package: package,
                              indexLabel: index + 1,
                              onOpenDetails: () {
                                _openPackageDetailsReadOnly(
                                  package,
                                  navigatorContext: dialogContext,
                                );
                              },
                              onRemove: () {
                                setPreviewState(() {
                                  removePreviewPackages(
                                    (nextPackages) =>
                                        nextPackages.removeAt(index),
                                  );
                                });
                                closeIfEmpty();
                              },
                            );
                          },
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF9E7B6),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(null),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.blueDark,
                                  side: const BorderSide(
                                    color: AppTheme.softBorder,
                                  ),
                                  minimumSize: const Size.fromHeight(50),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Text(
                                  'Cancelar',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: previewPackages.isEmpty
                                    ? null
                                    : () => Navigator.of(
                                        dialogContext,
                                      ).pop(previewPackages),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.blue,
                                  foregroundColor: AppTheme.yellowLight,
                                  minimumSize: const Size.fromHeight(50),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: Text(
                                  confirmButtonLabel,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  int _comparePackagesByActivity(
    InventoryPackageSummary first,
    InventoryPackageSummary second, {
    required bool newestFirst,
  }) {
    final firstDate = first.createdAt;
    final secondDate = second.createdAt;

    if (firstDate != null && secondDate != null) {
      final comparison = newestFirst
          ? secondDate.compareTo(firstDate)
          : firstDate.compareTo(secondDate);
      if (comparison != 0) {
        return comparison;
      }
    } else if (firstDate != null) {
      return newestFirst ? -1 : 1;
    } else if (secondDate != null) {
      return newestFirst ? 1 : -1;
    }

    final idComparison = newestFirst
        ? second.packageId.compareTo(first.packageId)
        : first.packageId.compareTo(second.packageId);
    if (idComparison != 0) {
      return idComparison;
    }

    final categoryComparison = _categoryPriority(
      first.packageType,
    ).compareTo(_categoryPriority(second.packageType));
    if (categoryComparison != 0) {
      return categoryComparison;
    }

    return first.code.compareTo(second.code);
  }

  bool _canAssignPackage(InventoryPackageSummary package) {
    final stateName = package.safeStateName;
    if (stateName == 'DEVOLUCION') {
      return true;
    }
    if (package.packageType == PackageCategory.ems ||
        package.packageType == PackageCategory.contrato) {
      return stateName == 'ALMACEN' || stateName == 'RECIBIDO';
    }
    return stateName == 'VENTANILLA';
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

  void _showFilterBottomSheet(List<InventoryPackageSummary> packages) {
    var selectedSort = _currentSort;
    var selectedFilters = Set<PackageCategory>.from(_activeFilters);
    var selectedStateFilters = Set<String>.from(_activeStateFilters);
    const availableCategories = [
      PackageCategory.ems,
      PackageCategory.certi,
      PackageCategory.contrato,
      PackageCategory.ordi,
    ];
    const availableStates = ['ALMACEN', 'DEVOLUCION', 'VENTANILLA', 'RECIBIDO'];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
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
                        child: DropdownButton<_InventorySortOption>(
                          value: selectedSort,
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
                          items: _InventorySortOption.values
                              .map((option) {
                                return DropdownMenuItem<_InventorySortOption>(
                                  value: option,
                                  child: Row(
                                    children: [
                                      Icon(
                                        option.icon,
                                        color: AppTheme.yellow,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        option.label,
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              })
                              .toList(growable: false),
                          onChanged: (value) {
                            if (value == null) return;
                            setSheetState(() {
                              selectedSort = value;
                            });
                            setState(() {
                              _currentSort = value;
                              _currentPage = 0;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'Filtrar Categorias',
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
                      children: availableCategories
                          .map((category) {
                            final isSelected = selectedFilters.contains(
                              category,
                            );
                            return FilterChip(
                              label: Text(category.label),
                              labelStyle: TextStyle(
                                color: isSelected
                                    ? AppTheme.blue
                                    : Colors.white,
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
                                setSheetState(() {
                                  if (selected) {
                                    selectedFilters.add(category);
                                  } else {
                                    selectedFilters.remove(category);
                                  }
                                });
                                setState(() {
                                  _activeFilters = selectedFilters;
                                  _currentPage = 0;
                                });
                              },
                            );
                          })
                          .toList(growable: false),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'Filtrar Estados',
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
                      children: availableStates
                          .map((stateName) {
                            final isSelected = selectedStateFilters.contains(
                              stateName,
                            );
                            return FilterChip(
                              label: Text(stateName),
                              labelStyle: TextStyle(
                                color: isSelected
                                    ? AppTheme.blue
                                    : Colors.white,
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
                                setSheetState(() {
                                  if (selected) {
                                    selectedStateFilters.add(stateName);
                                  } else {
                                    selectedStateFilters.remove(stateName);
                                  }
                                });
                                setState(() {
                                  _activeStateFilters = selectedStateFilters;
                                  _currentPage = 0;
                                });
                              },
                            );
                          })
                          .toList(growable: false),
                    ),
                    if (packages.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(
                        'Mostrando ${_filteredPackages(packages).length} paquetes',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      resizeToAvoidBottomInset: false,
      title: 'Asignar paquetes',
      floatingActionButton: FutureBuilder<CourierInventoryPackagesResult>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done ||
              snapshot.hasError) {
            return const SizedBox.shrink();
          }

          final packages =
              snapshot.data?.packages ?? const <InventoryPackageSummary>[];
          if (packages.isEmpty) {
            return const SizedBox.shrink();
          }

          return ValueListenableBuilder<Set<String>>(
            valueListenable: _selectedPackageKeysNotifier,
            builder: (context, selectedKeys, _) {
              final selectedPackages = _selectedPackagesFrom(packages);

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (selectedPackages.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: FloatingActionButton.extended(
                        heroTag: 'assign-selected-packages',
                        onPressed: _bulkAssigning
                            ? null
                            : () => _assignSelectedPackages(packages),
                        backgroundColor: AppTheme.actionYellowStrong,
                        foregroundColor: AppTheme.blueDark,
                        icon: _bulkAssigning
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.blueDark,
                                ),
                              )
                            : const Icon(Icons.done_all_rounded),
                        label: Text(
                          _bulkAssigning
                              ? 'Asignando'
                              : 'Revisar ${selectedPackages.length}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  FloatingActionButton.extended(
                    heroTag: 'filter-packages',
                    onPressed: () => _showFilterBottomSheet(packages),
                    backgroundColor: AppTheme.blue,
                    foregroundColor: AppTheme.yellowLight,
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.filter_list_rounded),
                        if (_activeFilters.isNotEmpty ||
                            _activeStateFilters.isNotEmpty)
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
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<CourierInventoryPackagesResult>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return _buildInitialLoadingView();
            }

            if (snapshot.hasError) {
              return ListView(
                padding: AppTheme.pagePadding,
                children: [
                  AppStatusMessageCard(
                    title: 'No se pudo cargar la asignación',
                    message: _mapError(snapshot.error!),
                    icon: Icons.error_outline_rounded,
                    iconColor: AppTheme.errorRed,
                  ),
                ],
              );
            }

            final result = snapshot.data!;
            final allPackages = result.packages;
            final filteredPackages = _filteredPackages(allPackages);
            final packages = _packagesForCurrentPage(filteredPackages);
            final totalPages = _totalPagesFor(filteredPackages);
            final currentPage = _effectivePageIndex(filteredPackages);
            final showingFrom = filteredPackages.isEmpty
                ? 0
                : (currentPage * _pageSize) + 1;
            final showingTo = filteredPackages.isEmpty
                ? 0
                : math.min(
                    (currentPage + 1) * _pageSize,
                    filteredPackages.length,
                  );

            return LayoutBuilder(
              builder: (context, constraints) {
                final isHandset = MediaQuery.sizeOf(context).shortestSide < 600;
                final canUseGrid = !isHandset && constraints.maxWidth >= 720;
                final useTwoColumns = canUseGrid && _preferGridLayout;

                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                      sliver: SliverToBoxAdapter(
                        child: _CourierInventoryHeaderCard(
                          courier: result.courier,
                          city: result.safeCity,
                          availablePackagesCount: allPackages.length,
                          visiblePackagesCount: filteredPackages.length,
                          hasActiveFilters:
                              _activeFilters.isNotEmpty ||
                              _activeStateFilters.isNotEmpty,
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                      sliver: SliverToBoxAdapter(
                        child: PackageTrackingQuickSearchBar(
                          controller: _packageSearchController,
                          focusNode: _packageSearchFocusNode,
                          loading: _searchingPackage,
                          onSearch: () => _searchPackageFromText(allPackages),
                          onScanWithCamera:
                              widget.onScanCodeWithCamera == null &&
                                  widget.onScanCodesWithCamera == null
                              ? null
                              : () => _scanPackageForAssignment(allPackages),
                        ),
                      ),
                    ),
                    if (filteredPackages.isNotEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                        sliver: SliverToBoxAdapter(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final selectionBar =
                                  ValueListenableBuilder<Set<String>>(
                                    valueListenable:
                                        _selectedPackageKeysNotifier,
                                    builder: (context, selectedKeys, _) {
                                      final selectedCount = filteredPackages
                                          .where(
                                            (package) => selectedKeys.contains(
                                              _packageKey(package),
                                            ),
                                          )
                                          .length;
                                      final currentPageFullySelected =
                                          packages.isNotEmpty &&
                                          packages.every(
                                            (package) => selectedKeys.contains(
                                              _packageKey(package),
                                            ),
                                          );

                                      return _InventorySelectionBar(
                                        selectedCount: selectedCount,
                                        allCurrentPageSelected:
                                            currentPageFullySelected,
                                        onSelectCurrentPage: packages.isEmpty
                                            ? null
                                            : () =>
                                                  _selectCurrentPage(packages),
                                        onClearCurrentPage: packages.isEmpty
                                            ? null
                                            : () => _clearCurrentPageSelection(
                                                packages,
                                              ),
                                      );
                                    },
                                  );

                              if (!canUseGrid) {
                                return selectionBar;
                              }
                              final viewToggle = AppViewModeToggle(
                                gridEnabled: useTwoColumns,
                                onGridEnabledChanged: (enabled) {
                                  setState(() => _preferGridLayout = enabled);
                                },
                                height: 56,
                              );

                              if (constraints.maxWidth >= 460) {
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(child: selectionBar),
                                    const SizedBox(width: 12),
                                    viewToggle,
                                  ],
                                );
                              }

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  selectionBar,
                                  const SizedBox(height: 8),
                                  viewToggle,
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    if (packages.isEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        sliver: SliverToBoxAdapter(
                          child: AppStatusMessageCard(
                            title:
                                _activeFilters.isNotEmpty ||
                                    _activeStateFilters.isNotEmpty
                                ? 'Sin resultados'
                                : 'Sin paquetes disponibles',
                            message:
                                _activeFilters.isNotEmpty ||
                                    _activeStateFilters.isNotEmpty
                                ? 'No encontramos paquetes que coincidan con los filtros seleccionados.'
                                : 'No encontramos paquetes disponibles para asignar en ${result.safeCity}.',
                            icon: Icons.inventory_2_outlined,
                          ),
                        ),
                      )
                    else if (useTwoColumns)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                mainAxisExtent: 216,
                              ),
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final package = packages[index];
                            return ValueListenableBuilder<Set<String>>(
                              valueListenable: _selectedPackageKeysNotifier,
                              builder: (context, selectedKeys, _) {
                                final packageKey = _packageKey(package);
                                final selected = selectedKeys.contains(
                                  packageKey,
                                );
                                return _InventoryPackageCard(
                                  cardKey: _cardKeyFor(package),
                                  package: package,
                                  selected: selected,
                                  onTap: () => _handlePackageCardTap(package),
                                  onViewInfo: () =>
                                      _openPackageDetailsReadOnly(package),
                                  onSelectedChanged: (_) =>
                                      _togglePackageSelection(package),
                                  onLongPressStart: (_) =>
                                      _startDragSelection(package, packages),
                                  onLongPressMoveUpdate: (details) =>
                                      _updateDragSelection(
                                        details.globalPosition,
                                      ),
                                  onLongPressEnd: (_) => _endDragSelection(),
                                  onLongPressCancel: _endDragSelection,
                                  compactActions: true,
                                );
                              },
                            );
                          }, childCount: packages.length),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                        sliver: SliverList.separated(
                          itemCount: packages.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final package = packages[index];
                            return ValueListenableBuilder<Set<String>>(
                              valueListenable: _selectedPackageKeysNotifier,
                              builder: (context, selectedKeys, _) {
                                final packageKey = _packageKey(package);
                                final selected = selectedKeys.contains(
                                  packageKey,
                                );
                                return _InventoryPackageCard(
                                  cardKey: _cardKeyFor(package),
                                  package: package,
                                  selected: selected,
                                  onTap: () => _handlePackageCardTap(package),
                                  onViewInfo: () =>
                                      _openPackageDetailsReadOnly(package),
                                  onSelectedChanged: (_) =>
                                      _togglePackageSelection(package),
                                  onLongPressStart: (_) =>
                                      _startDragSelection(package, packages),
                                  onLongPressMoveUpdate: (details) =>
                                      _updateDragSelection(
                                        details.globalPosition,
                                      ),
                                  onLongPressEnd: (_) => _endDragSelection(),
                                  onLongPressCancel: _endDragSelection,
                                  compactActions: false,
                                );
                              },
                            );
                          },
                        ),
                      ),
                    if (filteredPackages.isNotEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 112),
                        sliver: SliverToBoxAdapter(
                          child: _InventoryPaginationControls(
                            currentPage: currentPage,
                            totalPages: totalPages,
                            showingFrom: showingFrom,
                            showingTo: showingTo,
                            totalItems: filteredPackages.length,
                            onPageSelected: (page) {
                              setState(() {
                                _currentPage = page;
                              });
                            },
                          ),
                        ),
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
}

class _InventorySelectionBar extends StatelessWidget {
  const _InventorySelectionBar({
    required this.selectedCount,
    required this.allCurrentPageSelected,
    required this.onSelectCurrentPage,
    required this.onClearCurrentPage,
  });

  final int selectedCount;
  final bool allCurrentPageSelected;
  final VoidCallback? onSelectCurrentPage;
  final VoidCallback? onClearCurrentPage;

  @override
  Widget build(BuildContext context) {
    final selectionActionEnabled = allCurrentPageSelected
        ? onClearCurrentPage != null
        : onSelectCurrentPage != null;

    return AppSoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      backgroundColor: AppTheme.yellowField,
      borderRadius: AppTheme.radiusLarge,
      borderColor: AppTheme.softBorder,
      child: Row(
        children: [
          Expanded(
            child: _SelectionChip(
              icon: Icons.checklist_rounded,
              label: selectedCount == 1
                  ? '1 seleccionado'
                  : '$selectedCount seleccionados',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _SelectionActionChip(
              icon: allCurrentPageSelected
                  ? Icons.remove_done_rounded
                  : Icons.select_all_rounded,
              label: allCurrentPageSelected
                  ? 'Limpiar pagina'
                  : 'Seleccionar pagina',
              enabled: selectionActionEnabled,
              onTap: allCurrentPageSelected
                  ? onClearCurrentPage
                  : onSelectCurrentPage,
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryPaginationControls extends StatelessWidget {
  const _InventoryPaginationControls({
    required this.currentPage,
    required this.totalPages,
    required this.showingFrom,
    required this.showingTo,
    required this.totalItems,
    required this.onPageSelected,
  });

  final int currentPage;
  final int totalPages;
  final int showingFrom;
  final int showingTo;
  final int totalItems;
  final ValueChanged<int> onPageSelected;

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 390;
        return AppSoftCard(
          padding: EdgeInsets.fromLTRB(
            compact ? 10 : 12,
            9,
            compact ? 10 : 12,
            11,
          ),
          backgroundColor: AppTheme.yellowField,
          borderRadius: AppTheme.radiusLarge,
          borderColor: AppTheme.softBorder,
          child: compact
              ? _buildCompact(context, constraints.maxWidth)
              : _buildRegular(context),
        );
      },
    );
  }

  Widget _buildRegular(BuildContext context) {
    final pages = _regularPages();

    return Column(
      children: [
        _PaginationHeader(
          currentPage: currentPage,
          totalPages: totalPages,
          showingFrom: showingFrom,
          showingTo: showingTo,
          totalItems: totalItems,
        ),
        const SizedBox(height: 7),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            _PageNavButton(
              icon: Icons.chevron_left_rounded,
              enabled: currentPage > 0,
              onTap: () => onPageSelected(currentPage - 1),
            ),
            for (final page in pages)
              _PageNumberChip(
                label: '${page + 1}',
                selected: page == currentPage,
                onTap: () => onPageSelected(page),
              ),
            _PageNavButton(
              icon: Icons.chevron_right_rounded,
              enabled: currentPage < totalPages - 1,
              onTap: () => onPageSelected(currentPage + 1),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCompact(BuildContext context, double maxWidth) {
    final pages = _compactPages(maxWidth < 340 ? 3 : 5);
    final showFirstPage = pages.first > 0;
    final showLastPage = pages.last < totalPages - 1;

    return Column(
      children: [
        _PaginationHeader(
          currentPage: currentPage,
          totalPages: totalPages,
          showingFrom: showingFrom,
          showingTo: showingTo,
          totalItems: totalItems,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PageNavButton(
              icon: Icons.chevron_left_rounded,
              enabled: currentPage > 0,
              compact: true,
              onTap: () => onPageSelected(currentPage - 1),
            ),
            const SizedBox(width: 6),
            for (final page in pages) ...[
              _PageNumberChip(
                label: '${page + 1}',
                selected: page == currentPage,
                compact: true,
                onTap: () => onPageSelected(page),
              ),
              if (page != pages.last) const SizedBox(width: 6),
            ],
            const SizedBox(width: 6),
            _PageNavButton(
              icon: Icons.chevron_right_rounded,
              enabled: currentPage < totalPages - 1,
              compact: true,
              onTap: () => onPageSelected(currentPage + 1),
            ),
          ],
        ),
        if (showFirstPage || showLastPage) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (showFirstPage)
                _PageNumberChip(
                  label: '1',
                  selected: false,
                  compact: true,
                  onTap: () => onPageSelected(0),
                ),
              if (showFirstPage && showLastPage) const SizedBox(width: 8),
              if (showLastPage)
                _PageNumberChip(
                  label: '$totalPages',
                  selected: false,
                  compact: true,
                  wide: totalPages >= 100,
                  onTap: () => onPageSelected(totalPages - 1),
                ),
            ],
          ),
        ],
      ],
    );
  }

  List<int> _regularPages() {
    return <int>{
      0,
      totalPages - 1,
      currentPage,
      currentPage - 1,
      currentPage + 1,
      currentPage - 2,
      currentPage + 2,
    }.where((page) => page >= 0 && page < totalPages).toList()..sort();
  }

  List<int> _compactPages(int maxVisiblePages) {
    final visibleCount = math.min(totalPages, maxVisiblePages);
    var start = currentPage - 2;
    if (start < 0) start = 0;
    if (start + visibleCount > totalPages) {
      start = totalPages - visibleCount;
    }
    return List<int>.generate(visibleCount, (index) => start + index);
  }
}

class _PaginationHeader extends StatelessWidget {
  const _PaginationHeader({
    required this.currentPage,
    required this.totalPages,
    required this.showingFrom,
    required this.showingTo,
    required this.totalItems,
  });

  final int currentPage;
  final int totalPages;
  final int showingFrom;
  final int showingTo;
  final int totalItems;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Pagina ${currentPage + 1} de $totalPages',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: AppTheme.blueDark,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '$showingFrom-$showingTo de $totalItems paquetes',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppTheme.blueMid,
            fontWeight: FontWeight.w700,
            fontSize: 10.5,
          ),
        ),
      ],
    );
  }
}

class _BatchPreviewActions extends StatelessWidget {
  const _BatchPreviewActions({
    required this.totalItems,
    required this.onClearAll,
  });

  final int totalItems;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final enabled = totalItems > 0;
    return AppSoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      backgroundColor: AppTheme.yellowSurface,
      borderRadius: BorderRadius.circular(18),
      borderColor: AppTheme.softBorder,
      boxShadow: const [],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  totalItems == 1
                      ? '1 paquete seleccionado'
                      : '$totalItems paquetes seleccionados',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppTheme.blueDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: enabled ? onClearAll : null,
                icon: const Icon(Icons.clear_all_rounded, size: 18),
                label: const Text('Limpiar todo'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.errorRed,
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SelectedPackagePreviewTile extends StatelessWidget {
  const _SelectedPackagePreviewTile({
    required this.package,
    required this.indexLabel,
    required this.onOpenDetails,
    required this.onRemove,
  });

  final InventoryPackageSummary package;
  final int indexLabel;
  final VoidCallback onOpenDetails;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpenDetails,
        borderRadius: AppTheme.radiusLarge,
        child: AppSoftCard(
          padding: const EdgeInsets.all(12),
          backgroundColor: Colors.white,
          borderRadius: AppTheme.radiusLarge,
          borderColor: AppTheme.softBorder,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.actionYellowStrong,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$indexLabel',
                  style: const TextStyle(
                    color: AppTheme.blueDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      package.code,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppTheme.blueDark,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      package.safeRecipientName.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.blueMid,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _PreviewChip(label: package.packageTypeLabel),
                        _PreviewChip(label: package.safeStateName),
                        _PreviewChip(label: package.formattedDate),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: onRemove,
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.errorRed,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text(
                  'Quitar',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewChip extends StatelessWidget {
  const _PreviewChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.yellowField,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.softBorder),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.blueDark,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _CourierInventoryHeaderCard extends StatelessWidget {
  const _CourierInventoryHeaderCard({
    required this.courier,
    required this.city,
    required this.availablePackagesCount,
    required this.visiblePackagesCount,
    required this.hasActiveFilters,
  });

  final CourierSummary courier;
  final String city;
  final int availablePackagesCount;
  final int visiblePackagesCount;
  final bool hasActiveFilters;

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

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.blueDark, AppTheme.blue, AppTheme.blueMid],
        ),
        borderRadius: AppTheme.radiusXLarge,
        border: Border.all(color: const Color(0x80F5BD28), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x331B305F),
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
              _CourierAvatar(label: _initialsFor(courier.displayName)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      courier.displayName.toUpperCase(),
                      style: textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Ciudad operativa: $city',
                      style: textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HeaderChip(
                icon: Icons.assignment_rounded,
                label: '${courier.activeAssignmentsCount} asignaciones activas',
              ),
              _HeaderChip(
                icon: Icons.inventory_2_rounded,
                label: '$availablePackagesCount paquetes disponibles',
              ),
            ],
          ),
          if (hasActiveFilters) ...[
            const SizedBox(height: 12),
            Text(
              'Mostrando $visiblePackagesCount paquetes con los filtros actuales',
              style: textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SelectionChip extends StatelessWidget {
  const _SelectionChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.blue,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppTheme.yellowLight, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.yellowLight,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionActionChip extends StatelessWidget {
  const _SelectionActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          height: 40,
          decoration: BoxDecoration(
            color: enabled
                ? AppTheme.actionYellowStrong
                : const Color(0xFFE5D6A6),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: enabled ? AppTheme.strongBorder : AppTheme.softBorder,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: enabled ? AppTheme.blueDark : AppTheme.blueMid,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: enabled ? AppTheme.blueDark : AppTheme.blueMid,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageNavButton extends StatelessWidget {
  const _PageNavButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.compact = false,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 34.0 : 38.0;
    return IconButton.filledTonal(
      onPressed: enabled ? onTap : null,
      style: IconButton.styleFrom(
        backgroundColor: AppTheme.blue,
        disabledBackgroundColor: AppTheme.blue.withValues(alpha: 0.35),
        foregroundColor: AppTheme.yellowLight,
        fixedSize: Size(size, size),
        minimumSize: Size(size, size),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(icon, size: compact ? 18 : 20),
    );
  }
}

class _PageNumberChip extends StatelessWidget {
  const _PageNumberChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.compact = false,
    this.wide = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: compact ? 34 : 38,
      width: compact ? (wide ? 58 : 42) : null,
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8),
        onSelected: (_) => onTap(),
        selectedColor: AppTheme.actionYellowStrong,
        backgroundColor: AppTheme.yellowField,
        labelStyle: TextStyle(
          color: selected ? AppTheme.blueDark : AppTheme.blueMid,
          fontWeight: FontWeight.w900,
          fontSize: compact ? 14 : null,
        ),
        labelPadding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(
            color: selected ? AppTheme.strongBorder : AppTheme.softBorder,
          ),
        ),
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.yellowSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.softBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppTheme.blue),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: AppTheme.blue),
          ),
        ],
      ),
    );
  }
}

class _InventoryPackageCard extends StatelessWidget {
  const _InventoryPackageCard({
    required this.cardKey,
    required this.package,
    required this.selected,
    required this.onTap,
    required this.onViewInfo,
    required this.onSelectedChanged,
    required this.onLongPressStart,
    required this.onLongPressMoveUpdate,
    required this.onLongPressEnd,
    required this.onLongPressCancel,
    required this.compactActions,
  });

  final GlobalKey cardKey;
  final InventoryPackageSummary package;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onViewInfo;
  final ValueChanged<bool> onSelectedChanged;
  final GestureLongPressStartCallback onLongPressStart;
  final GestureLongPressMoveUpdateCallback onLongPressMoveUpdate;
  final GestureLongPressEndCallback onLongPressEnd;
  final VoidCallback onLongPressCancel;
  final bool compactActions;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final typeStyle = _packageTypeStyle(package.packageType, selected);
    final stateStyle = _packageStateStyle(package.safeStateName, selected);

    final textColorPrimary = selected ? AppTheme.yellow : AppTheme.blueDark;
    final textColorSecondary = selected
        ? AppTheme.yellowLight
        : AppTheme.blueDark;

    return GestureDetector(
      key: cardKey,
      behavior: HitTestBehavior.translucent,
      onLongPressStart: onLongPressStart,
      onLongPressMoveUpdate: onLongPressMoveUpdate,
      onLongPressEnd: onLongPressEnd,
      onLongPressCancel: onLongPressCancel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppTheme.radiusLarge,
          child: AppSoftCard(
            padding: EdgeInsets.fromLTRB(
              compactActions ? 8 : 12,
              compactActions ? 8 : 10,
              compactActions ? 8 : 12,
              compactActions ? 8 : 10,
            ),
            backgroundColor: selected
                ? AppTheme.blueDark
                : AppTheme.yellowField,
            borderRadius: AppTheme.radiusLarge,
            borderColor: selected ? AppTheme.yellow : AppTheme.softBorder,
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x3D000000),
                      blurRadius: 14,
                      offset: Offset(0, 6),
                    ),
                  ]
                : const [
                    BoxShadow(
                      color: Color(0x120F1E3D),
                      blurRadius: 12,
                      offset: Offset(0, 5),
                    ),
                  ],
            child: LayoutBuilder(
              builder: (context, constraints) {
                final useTrailingActionsColumn =
                    !compactActions && constraints.maxWidth >= 560;
                final detailsContent = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      package.code,
                      style: textTheme.titleMedium?.copyWith(
                        color: textColorPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: compactActions ? 15.5 : 16.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    SizedBox(
                      height: compactActions ? 32 : 36,
                      child: Text(
                        package.safeRecipientName.toUpperCase(),
                        style: textTheme.bodyMedium?.copyWith(
                          color: textColorSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: compactActions ? 12.5 : 13.5,
                          height: 1.12,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(height: compactActions ? 6 : 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: typeStyle.$1,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: typeStyle.$3),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.local_shipping_rounded,
                                size: 14,
                                color: typeStyle.$2,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                package.packageTypeLabel,
                                style: textTheme.labelSmall?.copyWith(
                                  color: typeStyle.$2,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: stateStyle.$1,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: stateStyle.$3),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                stateStyle.$4,
                                size: 14,
                                color: stateStyle.$2,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                package.safeStateName,
                                style: textTheme.labelSmall?.copyWith(
                                  color: stateStyle.$2,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: compactActions ? 8 : 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: selected ? AppTheme.blue : AppTheme.yellowLight,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: selected
                              ? const Color(0x33FFFFFF)
                              : const Color(0x80C9B58B),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 13,
                            color: selected
                                ? AppTheme.yellowLight
                                : AppTheme.blueMid,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            package.formattedDate,
                            style: textTheme.labelSmall?.copyWith(
                              color: selected
                                  ? AppTheme.yellowLight
                                  : AppTheme.blueMid,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );

                final selectionIndicator = selected
                    ? GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onSelectedChanged(false),
                        child: SizedBox(
                          width: 34,
                          height: 34,
                          child: Center(
                            child: Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppTheme.yellow,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppTheme.blue,
                                  width: 1.8,
                                ),
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                color: AppTheme.blueDark,
                                size: 19,
                              ),
                            ),
                          ),
                        ),
                      )
                    : null;

                final cardContent = compactActions
                    ? Stack(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 64,
                                    height: 64,
                                    child: const Image(
                                      image: AssetImage(
                                        'assets/images/package_box.png',
                                      ),
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        right: selectionIndicator == null
                                            ? 0
                                            : 34,
                                      ),
                                      child: detailsContent,
                                    ),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: _PackageActionRow(
                                  compact: true,
                                  onViewInfo: onViewInfo,
                                ),
                              ),
                            ],
                          ),
                          if (selectionIndicator != null)
                            Positioned(
                              top: 0,
                              right: 0,
                              child: selectionIndicator,
                            ),
                        ],
                      )
                    : !useTrailingActionsColumn
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 76,
                                height: 76,
                                child: const Image(
                                  image: AssetImage(
                                    'assets/images/package_box.png',
                                  ),
                                  fit: BoxFit.contain,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(child: detailsContent),
                              if (selectionIndicator != null) ...[
                                const SizedBox(width: 6),
                                selectionIndicator,
                              ],
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: _PackageActionRow(
                              compact: false,
                              onViewInfo: onViewInfo,
                            ),
                          ),
                        ],
                      )
                    : Stack(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 76,
                                height: 76,
                                child: const Image(
                                  image: AssetImage(
                                    'assets/images/package_box.png',
                                  ),
                                  fit: BoxFit.contain,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(child: detailsContent),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 176,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _ViewInfoPill(
                                      compact: false,
                                      onPressed: onViewInfo,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (selectionIndicator != null)
                            Positioned(
                              top: 0,
                              right: 0,
                              child: selectionIndicator,
                            ),
                        ],
                      );

                return compactActions
                    ? SizedBox.expand(child: cardContent)
                    : cardContent;
              },
            ),
          ),
        ),
      ),
    );
  }

  (Color, Color, Color) _packageTypeStyle(
    PackageCategory category,
    bool selected,
  ) {
    if (selected) {
      switch (category) {
        case PackageCategory.ems:
          return (const Color(0x33FFFFFF), Colors.white, Colors.white54);
        case PackageCategory.certi:
          return (const Color(0x33FFFFFF), Colors.white, Colors.white54);
        case PackageCategory.contrato:
          return (
            AppTheme.yellow.withValues(alpha: 0.25),
            AppTheme.yellow,
            AppTheme.yellow.withValues(alpha: 0.4),
          );
        case PackageCategory.ordi:
          return (
            AppTheme.yellow.withValues(alpha: 0.25),
            AppTheme.yellow,
            AppTheme.yellow.withValues(alpha: 0.4),
          );
      }
    }

    switch (category) {
      case PackageCategory.ems:
        return (AppTheme.blue, Colors.white, AppTheme.blueDark);
      case PackageCategory.certi:
        return (AppTheme.confirmBlue, Colors.white, AppTheme.confirmBlueDark);
      case PackageCategory.contrato:
        return (
          AppTheme.orangeWarm,
          AppTheme.blueDark,
          const Color(0xFFE1A73A),
        );
      case PackageCategory.ordi:
        return (AppTheme.yellow, AppTheme.blueDark, const Color(0xFFD8A722));
    }
  }

  (Color, Color, Color, IconData) _packageStateStyle(
    String stateName,
    bool selected,
  ) {
    if (selected) {
      switch (stateName.toUpperCase()) {
        case 'DEVOLUCION':
          return (
            AppTheme.errorRed.withValues(alpha: 0.25),
            const Color(0xFFFCA5A5),
            const Color(0x80FCA5A5),
            Icons.warning_rounded,
          );
        case 'ALMACEN':
          return (
            const Color(0x22FFFFFF),
            const Color(0xFFE7EEF9),
            const Color(0x44FFFFFF),
            Icons.inventory_2_rounded,
          );
        case 'RECIBIDO':
          return (
            const Color(0x22FFFFFF),
            const Color(0xFFE7EEF9),
            const Color(0x44FFFFFF),
            Icons.move_to_inbox_rounded,
          );
        case 'VENTANILLA':
        default:
          return (
            AppTheme.yellow.withValues(alpha: 0.25),
            AppTheme.yellow,
            AppTheme.yellow.withValues(alpha: 0.4),
            Icons.storefront_rounded,
          );
      }
    }

    switch (stateName.toUpperCase()) {
      case 'DEVOLUCION':
        return (
          AppTheme.errorSoft,
          AppTheme.errorRed,
          const Color(0xFFFCA5A5),
          Icons.warning_rounded,
        );
      case 'ALMACEN':
        return (
          const Color(0xFFE7EEF9),
          AppTheme.blue,
          const Color(0xFF9BB4DA),
          Icons.inventory_2_rounded,
        );
      case 'RECIBIDO':
        return (
          const Color(0xFFE7EEF9),
          AppTheme.blue,
          const Color(0xFF9BB4DA),
          Icons.move_to_inbox_rounded,
        );
      case 'VENTANILLA':
      default:
        return (
          const Color(0xFFF6D57F),
          AppTheme.blueDark,
          const Color(0xFFD8B14F),
          Icons.storefront_rounded,
        );
    }
  }
}

class _PackageActionRow extends StatelessWidget {
  const _PackageActionRow({required this.compact, required this.onViewInfo});

  final bool compact;
  final VoidCallback onViewInfo;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: _ViewInfoPill(compact: compact, onPressed: onViewInfo),
    );
  }
}

class _ViewInfoPill extends StatelessWidget {
  const _ViewInfoPill({required this.compact, required this.onPressed});

  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          width: double.infinity,
          height: compact ? 40 : 42,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF8D15E), Color(0xFFF3B81F)],
            ),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: AppTheme.strongBorder,
              width: AppTheme.borderWidth,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22A16207),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.visibility_rounded,
                  color: AppTheme.blueDark,
                  size: compact ? 18 : 18,
                ),
                SizedBox(width: compact ? 4 : 8),
                Flexible(
                  child: Text(
                    'Ver info',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        (compact
                                ? Theme.of(
                                    context,
                                  ).textTheme.labelMedium?.copyWith(
                                    fontSize: 13.2,
                                    fontWeight: FontWeight.w900,
                                  )
                                : Theme.of(
                                    context,
                                  ).textTheme.labelLarge?.copyWith(
                                    fontSize: 14.0,
                                    fontWeight: FontWeight.w900,
                                  ))
                            ?.copyWith(color: AppTheme.blueDark),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CourierAvatar extends StatelessWidget {
  const _CourierAvatar({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.actionYellowStrong,
        borderRadius: BorderRadius.circular(17),
        boxShadow: const [
          BoxShadow(
            color: Color(0x181B305F),
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: AppTheme.blueDark,
          fontWeight: FontWeight.w900,
          fontSize: 18,
        ),
      ),
    );
  }
}
