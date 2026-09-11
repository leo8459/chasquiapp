import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

import 'package:scan_agbc/nucleo/inyeccion/app_services.dart';
import 'package:scan_agbc/nucleo/tema/app_theme.dart';
import 'package:scan_agbc/nucleo/componentes/app_page_scaffold.dart';
import 'package:scan_agbc/nucleo/componentes/app_user_drawer.dart';
import 'package:scan_agbc/funcionalidades/autenticacion/dominio/modelos/authenticated_user.dart';
import 'package:scan_agbc/funcionalidades/autenticacion/dominio/utilidades/user_role_permissions.dart';
import 'package:scan_agbc/funcionalidades/autenticacion/presentacion/paginas/login_page.dart';
import 'package:scan_agbc/funcionalidades/bitacoras/presentacion/paginas/bitacoras_page.dart';
import 'package:scan_agbc/funcionalidades/gasolina/presentacion/paginas/gasolinas_page.dart';
import 'package:scan_agbc/funcionalidades/mantenimiento/presentacion/paginas/mantenimientos_page.dart';
import 'package:scan_agbc/funcionalidades/inicio/presentacion/componentes/app_sidebar.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/assigned_package_summary.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/available_couriers_result.dart';
import 'package:scan_agbc/funcionalidades/cartero/presentacion/paginas/self_package_assignment_page.dart';
import 'package:scan_agbc/funcionalidades/cartero/presentacion/paginas/contract_package_pickup_page.dart';
import 'package:scan_agbc/funcionalidades/gestion/presentacion/paginas/courier_assignments_lookup_page.dart';
import 'package:scan_agbc/funcionalidades/gestion/presentacion/paginas/recent_regional_assignments_page.dart';
import 'package:scan_agbc/funcionalidades/seguimiento/presentacion/componentes/package_tracking_panel.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/presentacion/controladores/scanner_controller.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/presentacion/paginas/scanner_page.dart';

enum UserArea {
  carteros,
  clasificaciones,
  gestion,
  consulta,
  administrador,
  modeSelection,
}

extension UserAreaX on UserArea {
  String get label {
    switch (this) {
      case UserArea.carteros:
        return 'Carteros';
      case UserArea.clasificaciones:
        return 'Clasificaciones';
      case UserArea.gestion:
        return 'Gestión';
      case UserArea.consulta:
        return 'Consulta';
      case UserArea.administrador:
        return 'Administrador';
      case UserArea.modeSelection:
        return 'Seleccionar Área';
    }
  }

  IconData get icon {
    switch (this) {
      case UserArea.carteros:
        return Icons.route_rounded;
      case UserArea.clasificaciones:
        return Icons.qr_code_scanner_rounded;
      case UserArea.gestion:
        return Icons.badge_rounded;
      case UserArea.consulta:
        return Icons.search_rounded;
      case UserArea.administrador:
        return Icons.admin_panel_settings_rounded;
      case UserArea.modeSelection:
        return Icons.switch_account_rounded;
    }
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.currentUser,
    required this.services,
    required this.area,
  });

  final AuthenticatedUser currentUser;
  final AppServices services;
  final UserArea area;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final _sessionSecurityService = widget.services.sessionSecurityService;
  late final _biometricAuthService = widget.services.biometricAuthService;
  late final _permissions = UserRolePermissions.fromRoles(
    widget.currentUser.roles,
  );
  ScannerController? _clasificacionesScannerController;
  ScannerController? _packageLookupScannerController;
  bool _rememberSession = false;
  bool _useBiometric = false;
  bool _biometricAvailable = false;
  Future<List<AssignedPackageSummary>>? _recentRegionalAssignmentsFuture;
  Future<AvailableCouriersResult>? _couriersFuture;

  bool get _showsModeSelection => widget.area == UserArea.modeSelection;

  bool get _showsManagementTools =>
      widget.area == UserArea.gestion || widget.area == UserArea.administrador;

  bool get _canSearchPackages =>
      !_showsModeSelection && _permissions.canSearchPackages;

  bool get _canSearchCourierByCi =>
      _showsManagementTools && _permissions.canSearchCourierByCi;

  bool get _canBrowseCouriers =>
      widget.area == UserArea.carteros && _permissions.canSearchCourierByCi;

  bool get _canRegisterPackages =>
      widget.area == UserArea.clasificaciones &&
      _permissions.canRegisterPackages;

  bool get _showsScannerAsRoot =>
      widget.area == UserArea.clasificaciones && _canRegisterPackages;

  List<AppDrawerInfoItem> _buildDrawerInfoItems() {
    final items = <AppDrawerInfoItem>[];

    if (_canSearchPackages) {
      items.add(
        const AppDrawerInfoItem(
          icon: Icons.search_rounded,
          title: 'Consulta por código',
          subtitle:
              'Busca el paquete y revisa ciudad, destinatario, teléfono y dirección.',
        ),
      );
    }

    if (_canSearchCourierByCi) {
      items.add(
        const AppDrawerInfoItem(
          icon: Icons.badge_rounded,
          title: 'Asignar paquetes',
          subtitle:
              'Busca un cartero por nombre y revisa sus asignaciones activas.',
        ),
      );
    }

    if (_canBrowseCouriers) {
      items.add(
        const AppDrawerInfoItem(
          icon: Icons.groups_2_rounded,
          title: 'Buscar carteros',
          subtitle: 'Consulta carteros y abre sus asignaciones activas.',
        ),
      );
    }

    if (_canRegisterPackages) {
      items.add(
        const AppDrawerInfoItem(
          icon: Icons.inventory_2_rounded,
          title: 'Clasificaciones',
          subtitle: 'Registra la ficha del paquete desde el flujo operativo.',
        ),
      );
    }

    return items;
  }

  @override
  void initState() {
    super.initState();
    if (_showsScannerAsRoot) {
      _clasificacionesScannerController = ScannerController(
        scanRepository: widget.services.scannerRepository,
      );
    } else {
      if (_canSearchPackages || _canSearchCourierByCi || _canBrowseCouriers) {
        _packageLookupScannerController = ScannerController(
          scanRepository: widget.services.scannerRepository,
          cameraResolutionPreset: ResolutionPreset.high,
          scanAreaWidthFactor: 0.88,
          scanAreaHeightFactor: 0.18,
          barcodeFormats: const <BarcodeFormat>[BarcodeFormat.code128],
        );
      }
      _loadSecurityPreferences();
    }
    if (_canSearchCourierByCi || _canBrowseCouriers) {
      _couriersFuture = widget.services.packageTrackingRepository
          .findAvailableCouriers(allCities: _canBrowseCouriers);
    }
    if (_canSearchCourierByCi) {
      _recentRegionalAssignmentsFuture = widget
          .services
          .packageTrackingRepository
          .findRecentRegionalAssignments();
      unawaited(
        widget.services.packageTrackingRepository.preloadManagementInventory(),
      );
    }
  }

  @override
  void dispose() {
    _clasificacionesScannerController?.dispose();
    _packageLookupScannerController?.dispose();
    super.dispose();
  }

  Future<void> _loadSecurityPreferences() async {
    await _sessionSecurityService.setRememberSessionEnabled(true);
    const rememberSessionEnabled = true;
    final savedEmail = await _sessionSecurityService.readSessionEmail();
    final biometricEnabledForUser = await _sessionSecurityService
        .isBiometricEnabledFor(widget.currentUser.alias);
    final biometricAvailable = await _biometricAuthService.isAvailable();

    if (rememberSessionEnabled &&
        (savedEmail == null || savedEmail.trim().isEmpty)) {
      await _sessionSecurityService.saveSessionEmail(widget.currentUser.alias);
    }

    if (!mounted) return;
    setState(() {
      _rememberSession = rememberSessionEnabled;
      _useBiometric = _rememberSession && biometricEnabledForUser;
      _biometricAvailable = biometricAvailable;
    });
  }

  Future<void> _setRememberSession(bool enabled) async {
    if (enabled) {
      await _sessionSecurityService.setRememberSessionEnabled(true);
      await _sessionSecurityService.saveSessionEmail(widget.currentUser.alias);
      await widget.services.persistRememberedAuthState(widget.currentUser);
      if (!mounted) return;
      setState(() {
        _rememberSession = true;
      });
      return;
    }

    await _sessionSecurityService.clearSession();
    if (!mounted) return;
    setState(() {
      _rememberSession = false;
      _useBiometric = false;
    });
  }

  Future<void> _setUseBiometric(bool enabled) async {
    if (!_rememberSession) return;
    if (!_biometricAvailable && enabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este dispositivo no tiene biometria disponible.'),
        ),
      );
      return;
    }

    await _sessionSecurityService.setBiometricEnabledFor(
      widget.currentUser.alias,
      enabled,
    );
    if (!mounted) return;
    setState(() {
      _useBiometric = enabled;
    });
  }

  Future<void> _openCourierLookup(CourierLookupMode mode) async {
    final allCities = mode == CourierLookupMode.viewAssignments;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CourierAssignmentsLookupPage(
          repository: widget.services.packageTrackingRepository,
          onScanCodeWithCamera: _scanPackageCodeFromCamera,
          onScanCodesWithCamera: _scanPackageCodesFromCamera,
          initialCouriersFuture: _couriersFuture,
          mode: mode,
        ),
      ),
    );
    _couriersFuture = widget.services.packageTrackingRepository
        .findAvailableCouriers(allCities: allCities);
  }

  Future<void> _openCourierManagementLookup() =>
      _openCourierLookup(CourierLookupMode.assignPackages);

  Future<void> _openCourierAssignmentsLookup() =>
      _openCourierLookup(CourierLookupMode.viewAssignments);

  Future<void> _openRecentAssignments() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecentRegionalAssignmentsPage(
          repository: widget.services.packageTrackingRepository,
          initialAssignmentsFuture: _recentRegionalAssignmentsFuture,
        ),
      ),
    );
    _recentRegionalAssignmentsFuture = widget.services.packageTrackingRepository
        .findRecentRegionalAssignments();
  }

  Future<void> _openSelfPackageAssignment() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SelfPackageAssignmentPage(
          repository: widget.services.packageTrackingRepository,
          onScanCodeWithCamera: _scanPackageCodeFromCamera,
        ),
      ),
    );
  }

  Future<void> _openContractPackagePickup() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ContractPackagePickupPage(
          repository: widget.services.packageTrackingRepository,
          onScanCodeWithCamera: _scanPackageCodeFromCamera,
        ),
      ),
    );
  }

  Future<void> _openBitacoras() async {
    Navigator.of(context).pop();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            BitacorasPage(repository: widget.services.bitacoraRepository),
      ),
    );
  }

  Future<void> _openGasolina() async {
    Navigator.of(context).pop();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GasolinasPage(
          repository: widget.services.gasolinaRepository,
          bitacoraRepository: widget.services.bitacoraRepository,
        ),
      ),
    );
  }

  Future<void> _openMantenimientos() async {
    Navigator.of(context).pop();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MantenimientosPage(
          repository: widget.services.mantenimientoRepository,
        ),
      ),
    );
  }

  List<AppDrawerActionItem> _buildDrawerActions() {
    return <AppDrawerActionItem>[
      AppDrawerActionItem(
        icon: Icons.menu_book_rounded,
        title: 'Bitácoras',
        onTap: _openBitacoras,
      ),
      AppDrawerActionItem(
        icon: Icons.local_gas_station_rounded,
        title: 'Gasolina',
        onTap: _openGasolina,
      ),
      AppDrawerActionItem(
        icon: Icons.build_circle_outlined,
        title: 'Solicitar mantenimiento',
        onTap: _openMantenimientos,
      ),
    ];
  }

  Future<void> _openScanner() async {
    final scannerController = ScannerController(
      scanRepository: widget.services.scannerRepository,
    );
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScannerPage(
          controller: scannerController,
          services: widget.services,
          currentUser: widget.currentUser,
        ),
      ),
    );
  }

  Future<String?> _scanPackageCodeFromCamera() {
    final scannerController =
        _packageLookupScannerController ??
        ScannerController(
          scanRepository: widget.services.scannerRepository,
          cameraResolutionPreset: ResolutionPreset.high,
          scanAreaWidthFactor: 0.88,
          scanAreaHeightFactor: 0.18,
          barcodeFormats: const <BarcodeFormat>[BarcodeFormat.code128],
        );
    _packageLookupScannerController ??= scannerController;
    scannerController.prepareCamera();
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ScannerPage(
          controller: scannerController,
          services: widget.services,
          currentUser: widget.currentUser,
          mode: ScannerPageMode.packageLookup,
          disposeControllerOnClose: false,
        ),
      ),
    );
  }

  Future<List<String>?> _scanPackageCodesFromCamera(
    Set<String> availablePackageCodes,
    Set<String> initiallySelectedCodes,
    ValueChanged<Set<String>> onSelectedCodesChanged,
    Future<List<String>?> Function(List<String> selectedCodes)
    onReviewSelectedCodes,
  ) {
    final scannerController =
        _packageLookupScannerController ??
        ScannerController(
          scanRepository: widget.services.scannerRepository,
          cameraResolutionPreset: ResolutionPreset.high,
          scanAreaWidthFactor: 0.88,
          scanAreaHeightFactor: 0.18,
          barcodeFormats: const <BarcodeFormat>[BarcodeFormat.code128],
        );
    _packageLookupScannerController ??= scannerController;
    scannerController.prepareCamera();
    return Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => ScannerPage(
          controller: scannerController,
          services: widget.services,
          currentUser: widget.currentUser,
          mode: ScannerPageMode.packageLookup,
          disposeControllerOnClose: false,
          collectMultiplePackageCodes: true,
          availablePackageCodes: availablePackageCodes,
          initiallySelectedPackageCodes: initiallySelectedCodes,
          onSelectedPackageCodesChanged: onSelectedCodesChanged,
          onReviewPackageCodes: onReviewSelectedCodes,
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await widget.services.clearActiveSession();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginPage(services: widget.services)),
      (route) => false,
    );
  }

  void _openAreaMode(UserArea area) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HomePage(
          currentUser: widget.currentUser,
          services: widget.services,
          area: area,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showsScannerAsRoot) {
      return ScannerPage(
        controller: _clasificacionesScannerController!,
        services: widget.services,
        currentUser: widget.currentUser,
      );
    }

    if (_showsModeSelection) {
      return AppPageScaffold(
        resizeToAvoidBottomInset: false,
        drawer: AppSidebar(
          displayName: widget.currentUser.name,
          email: widget.currentUser.email,
          modeLabel: widget.area.label,
          modeIcon: widget.area.icon,
          rememberSession: _rememberSession,
          useBiometric: _useBiometric,
          biometricAvailable: _biometricAvailable,
          onRememberSessionChanged: _setRememberSession,
          onUseBiometricChanged: _setUseBiometric,
          onLogout: _logout,
          services: widget.services,
          actionItems: _buildDrawerActions(),
          infoItems: [
            const AppDrawerInfoItem(
              icon: Icons.badge_rounded,
              title: 'Gestión',
              subtitle: 'Administra carteros y asignaciones urbanas.',
            ),
            const AppDrawerInfoItem(
              icon: Icons.route_rounded,
              title: 'Cartero',
              subtitle: 'Revisa tus paquetes asignados.',
            ),
            if (_permissions.canRegisterPackages)
              const AppDrawerInfoItem(
                icon: Icons.qr_code_scanner_rounded,
                title: 'Clasificaciones',
                subtitle: 'Registra paquetes desde el flujo operativo.',
              ),
          ],
        ),
        title: widget.area.label,
        backgroundDecoration: AppTheme.pageDecoration,
        bodyPadding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 36,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE4A3),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: AppTheme.blue.withValues(alpha: 0.50),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.inventory_2_outlined,
                      color: AppTheme.blue,
                      size: 68,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Módulos Disponibles',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.blue,
                        fontFamily: AppTheme.fontFamily,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: 40,
                      height: 3,
                      decoration: BoxDecoration(
                        color: AppTheme.yellow,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Elija el módulo que desea gestionar.',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.blue.withValues(alpha: 0.6),
                        fontFamily: AppTheme.fontFamily,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    _AreaOptionCard(
                      title: 'Gestión',
                      subtitle: 'Administración de tareas y paquetes.',
                      icon: Icons.assignment_outlined,
                      onTap: () => _openAreaMode(UserArea.gestion),
                    ),
                    const SizedBox(height: 16),
                    _AreaOptionCard(
                      title: 'Carteros',
                      subtitle: 'Gestión del personal de reparto.',
                      icon: Icons.person_outline_rounded,
                      onTap: () => _openAreaMode(UserArea.carteros),
                    ),
                    if (_permissions.canRegisterPackages) ...[
                      const SizedBox(height: 16),
                      _AreaOptionCard(
                        title: 'Clasificaciones',
                        subtitle: 'Registro operativo de paquetes.',
                        icon: Icons.qr_code_scanner_rounded,
                        onTap: () => _openAreaMode(UserArea.clasificaciones),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return AppPageScaffold(
      resizeToAvoidBottomInset: false,
      drawer: AppSidebar(
        displayName: widget.currentUser.name,
        email: widget.currentUser.email,
        modeLabel: widget.area.label,
        modeIcon: widget.area.icon,
        rememberSession: _rememberSession,
        useBiometric: _useBiometric,
        biometricAvailable: _biometricAvailable,
        onRememberSessionChanged: _setRememberSession,
        onUseBiometricChanged: _setUseBiometric,
        onLogout: _logout,
        services: widget.services,
        actionItems: _buildDrawerActions(),
        infoItems: _buildDrawerInfoItems(),
      ),
      title: widget.area.label,
      backgroundDecoration: AppTheme.pageDecoration,
      bodyPadding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      body: PackageTrackingPanel(
        repository: widget.services.packageTrackingRepository,
        showPackageSearch: _canSearchPackages,
        onOpenCourierLookup: _canSearchCourierByCi
            ? _openCourierManagementLookup
            : (_canBrowseCouriers ? _openCourierAssignmentsLookup : null),
        courierLookupActionIcon: _canBrowseCouriers
            ? Icons.groups_2_rounded
            : Icons.badge_rounded,
        courierLookupActionTitle: _canBrowseCouriers
            ? 'Buscar cartero'
            : 'Asignar paquetes',
        courierLookupActionSubtitle: _canBrowseCouriers
            ? 'Busca un cartero y abre sus asignaciones activas.'
            : 'Busca por nombre y revisa sus asignaciones activas.',
        onOpenRecentAssignments: _canSearchCourierByCi
            ? _openRecentAssignments
            : null,
        onOpenSelfAssignment: _openSelfPackageAssignment,
        onOpenContractPickup: _openContractPackagePickup,
        onOpenScanner: _canRegisterPackages ? _openScanner : null,
        scannerActionTitle: 'Clasificaciones',
        scannerActionSubtitle:
            'Ingresa al flujo operativo para registrar la ficha del paquete.',
        onScanCodeWithCamera: _scanPackageCodeFromCamera,
      ),
    );
  }
}

class _AreaOptionCard extends StatelessWidget {
  const _AreaOptionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const borderRadius = BorderRadius.all(Radius.circular(22));

    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        splashColor: Colors.white.withValues(alpha: 0.08),
        highlightColor: Colors.white.withValues(alpha: 0.05),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.buildActionDecoration(
            borderRadius: borderRadius,
            boxShadow: const [
              BoxShadow(
                color: Color(0x120F1E3D),
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              DecoratedBox(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.strongShadow,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppTheme.actionYellowStrong,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.strongBorder, width: 2),
                  ),
                  child: Icon(icon, color: AppTheme.blueDark, size: 26),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontFamily: AppTheme.fontFamily,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.8),
                        fontFamily: AppTheme.fontFamily,
                        fontWeight: FontWeight.w500,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.yellow,
                size: 30,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
