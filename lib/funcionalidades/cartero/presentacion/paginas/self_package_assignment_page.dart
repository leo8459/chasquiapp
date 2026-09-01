import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:scan_agbc/nucleo/componentes/app_cards.dart';
import 'package:scan_agbc/nucleo/componentes/app_feedback_banner.dart';
import 'package:scan_agbc/nucleo/componentes/app_page_scaffold.dart';
import 'package:scan_agbc/nucleo/tema/app_theme.dart';
import 'package:scan_agbc/nucleo/utilidades/user_friendly_error_mapper.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/assigned_package_summary.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/repositorios/package_tracking_repository.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/utilidades/package_code_classifier.dart';
import 'package:scan_agbc/funcionalidades/seguimiento/presentacion/componentes/package_tracking_search_card.dart';
import 'package:scan_agbc/funcionalidades/cartero/presentacion/paginas/siop_package_delivery_page.dart';

class SelfPackageAssignmentPage extends StatefulWidget {
  const SelfPackageAssignmentPage({
    super.key,
    required this.repository,
    this.onScanCodeWithCamera,
  });

  final PackageTrackingRepository repository;
  final Future<String?> Function()? onScanCodeWithCamera;

  @override
  State<SelfPackageAssignmentPage> createState() =>
      _SelfPackageAssignmentPageState();
}

class _SelfPackageAssignmentPageState extends State<SelfPackageAssignmentPage> {
  final TextEditingController _codeController = TextEditingController();
  final FocusNode _codeFocusNode = FocusNode();
  final Set<String> _selectedCodes = <String>{};
  late Future<List<AssignedPackageSummary>> _assignmentsFuture =
      _loadAssignments();
  List<AssignedPackageSummary> _loadedAssignments =
      const <AssignedPackageSummary>[];
  bool _scanning = false;
  bool _assigning = false;
  int? _deliveringAssignmentId;

  bool get _busy => _scanning || _assigning || _deliveringAssignmentId != null;

  @override
  void dispose() {
    _codeController.dispose();
    _codeFocusNode.dispose();
    super.dispose();
  }

  Future<List<AssignedPackageSummary>> _loadAssignments() async {
    final assignments = await widget.repository.findMySiopAssignedPackages();
    _loadedAssignments = assignments;
    return assignments;
  }

  Future<void> _reload() async {
    final future = _loadAssignments();
    setState(() => _assignmentsFuture = future);
    await future;
  }

  Future<void> _addTypedCode() => _addCode(_codeController.text);

  Future<void> _pasteCode() async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final code = clipboard?.text ?? '';
    if (code.trim().isEmpty) return;
    await _addCode(code);
  }

  Future<void> _scanCode() async {
    final scan = widget.onScanCodeWithCamera;
    if (scan == null || _busy) return;
    setState(() => _scanning = true);
    try {
      final code = await scan();
      if (!mounted || code == null || code.trim().isEmpty) return;
      await _addCode(code);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _addCode(String rawCode) async {
    final validation = PackageCodeClassifier.validateForSearch(rawCode);
    if (!validation.isValid) {
      showAppFeedbackBanner(
        context,
        validation.errorMessage ?? 'Ingresa un código de paquete válido.',
        tone: AppFeedbackTone.error,
      );
      return;
    }

    final code = validation.normalizedCode;
    final alreadyAssigned = _loadedAssignments.any(
      (item) => PackageCodeClassifier.normalize(item.code) == code,
    );
    if (alreadyAssigned) {
      showAppFeedbackBanner(
        context,
        '$code ya está asignado a tu cuenta.',
        tone: AppFeedbackTone.info,
      );
      return;
    }

    setState(() {
      _selectedCodes.add(code);
      _codeController.clear();
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _assignSelected() async {
    if (_selectedCodes.isEmpty || _assigning) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar asignación'),
        content: Text(
          'Se asignarán ${_selectedCodes.length} paquete(s) a tu cuenta SIOP.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Asignar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _assigning = true);
    try {
      try {
        await widget.repository.assignSiopPackagesToMe(
          _selectedCodes.toList(growable: false),
        );
      } catch (error) {
        if (!mounted) return;
        showAppFeedbackBanner(
          context,
          UserFriendlyErrorMapper.message(
            error,
            fallback: 'No pudimos asignar los paquetes seleccionados.',
          ),
          tone: AppFeedbackTone.error,
        );
        return;
      }

      if (!mounted) return;
      setState(_selectedCodes.clear);
      var refreshed = true;
      try {
        await _reload();
      } catch (_) {
        refreshed = false;
      }
      if (!mounted) return;
      showAppFeedbackBanner(
        context,
        refreshed
            ? 'Paquetes asignados correctamente.'
            : 'Paquetes asignados. Desliza hacia abajo para actualizar la lista.',
        tone: refreshed ? AppFeedbackTone.success : AppFeedbackTone.info,
      );
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
  }

  Future<void> _deliverPackage(AssignedPackageSummary assignment) async {
    if (_deliveringAssignmentId != null) return;
    setState(() => _deliveringAssignmentId = assignment.assignmentId);
    try {
      final delivered = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => SiopPackageDeliveryPage(
            assignment: assignment,
            repository: widget.repository,
          ),
        ),
      );
      if (delivered != true || !mounted) return;
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      showAppFeedbackBanner(
        context,
        'Paquete ${assignment.code} entregado correctamente.',
        tone: AppFeedbackTone.success,
      );
    } finally {
      if (mounted) setState(() => _deliveringAssignmentId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedCodes = _selectedCodes.toList()..sort();

    return AppPageScaffold(
      title: 'Asignarse paquetes',
      resizeToAvoidBottomInset: true,
      body: RefreshIndicator(
        color: AppTheme.blue,
        onRefresh: _reload,
        child: ListView(
          padding: AppTheme.pagePadding,
          children: [
            PackageTrackingSearchCard(
              controller: _codeController,
              focusNode: _codeFocusNode,
              loading: _busy,
              title: 'Agregar paquete',
              hintText: 'Escribe o escanea el código',
              buttonLabel: 'Agregar a prelista',
              loadingLabel: _scanning ? 'Escaneando...' : 'Procesando...',
              helperText:
                  'Agrega uno o varios códigos antes de confirmar la asignación.',
              onSearch: _addTypedCode,
              onPasteCode: _pasteCode,
              onScanWithCamera: widget.onScanCodeWithCamera == null
                  ? null
                  : _scanCode,
            ),
            const SizedBox(height: 16),
            _SelectionPreviewCard(
              codes: selectedCodes,
              assigning: _assigning,
              onRemove: (code) => setState(() => _selectedCodes.remove(code)),
              onClear: () => setState(_selectedCodes.clear),
              onAssign: _assignSelected,
            ),
            const SizedBox(height: 20),
            FutureBuilder<List<AssignedPackageSummary>>(
              future: _assignmentsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(28),
                      child: CircularProgressIndicator(color: AppTheme.blue),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return _MessageCard(
                    icon: Icons.lock_outline_rounded,
                    title: 'No pudimos cargar tus asignaciones',
                    message: UserFriendlyErrorMapper.message(
                      snapshot.error!,
                      fallback: 'Intenta nuevamente.',
                    ),
                  );
                }
                final assignments = snapshot.data ?? const [];
                return _AssignedPackagesSection(
                  assignments: assignments,
                  deliveringAssignmentId: _deliveringAssignmentId,
                  onDeliver: _deliverPackage,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionPreviewCard extends StatelessWidget {
  const _SelectionPreviewCard({
    required this.codes,
    required this.assigning,
    required this.onRemove,
    required this.onClear,
    required this.onAssign,
  });

  final List<String> codes;
  final bool assigning;
  final ValueChanged<String> onRemove;
  final VoidCallback onClear;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    return AppPanelCard(
      padding: const EdgeInsets.all(16),
      backgroundColor: AppTheme.yellowSoft,
      borderColor: AppTheme.softBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.playlist_add_check_rounded,
                color: AppTheme.blue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Prelista (${codes.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppTheme.blueDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (codes.isNotEmpty)
                TextButton(onPressed: onClear, child: const Text('Limpiar')),
            ],
          ),
          const SizedBox(height: 10),
          if (codes.isEmpty)
            const Text('Todavía no seleccionaste paquetes.')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: codes
                  .map(
                    (code) => InputChip(
                      label: Text(code),
                      onDeleted: assigning ? null : () => onRemove(code),
                    ),
                  )
                  .toList(growable: false),
            ),
          if (codes.isNotEmpty) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: assigning ? null : onAssign,
              icon: assigning
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.assignment_turned_in_rounded),
              label: Text(
                assigning
                    ? 'Asignando...'
                    : 'Asignar ${codes.length} paquete(s)',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AssignedPackagesSection extends StatelessWidget {
  const _AssignedPackagesSection({
    required this.assignments,
    required this.deliveringAssignmentId,
    required this.onDeliver,
  });

  final List<AssignedPackageSummary> assignments;
  final int? deliveringAssignmentId;
  final ValueChanged<AssignedPackageSummary> onDeliver;

  String _displayValue(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? 'No registrado' : normalized;
  }

  Future<void> _showPackageDetails(
    BuildContext context,
    AssignedPackageSummary assignment,
  ) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(24, 22, 16, 8),
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        title: Row(
          children: [
            const Icon(Icons.inventory_2_rounded, color: AppTheme.blue),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                assignment.code,
                style: const TextStyle(
                  color: AppTheme.blueDark,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AssignmentDetailRow(
                icon: Icons.category_rounded,
                label: 'Tipo de paquete',
                value: assignment.displayPackageType,
              ),
              _AssignmentDetailRow(
                icon: Icons.person_rounded,
                label: 'Destinatario',
                value: _displayValue(assignment.recipientName),
              ),
              _AssignmentDetailRow(
                icon: Icons.phone_rounded,
                label: 'Teléfono del destinatario',
                value: _displayValue(assignment.recipientPhone),
              ),
              _AssignmentDetailRow(
                icon: Icons.location_on_rounded,
                label: 'Dirección del destinatario',
                value: _displayValue(assignment.recipientAddress),
                isLast: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cerrar'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onDeliver(assignment);
            },
            icon: const Icon(Icons.local_shipping_rounded),
            label: const Text('Entregar paquete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Paquetes asignados (${assignments.length})',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: AppTheme.blueDark,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        if (assignments.isEmpty)
          const _MessageCard(
            icon: Icons.inventory_2_outlined,
            title: 'Sin paquetes asignados',
            message: 'Cuando te asignes paquetes aparecerán en esta lista.',
          )
        else
          ...assignments.map(
            (assignment) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Semantics(
                button: true,
                label: 'Ver datos del paquete ${assignment.code}',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: deliveringAssignmentId == null
                      ? () => _showPackageDetails(context, assignment)
                      : null,
                  child: AppSoftCard(
                    padding: const EdgeInsets.all(14),
                    backgroundColor: AppTheme.yellowField,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.inventory_2_rounded,
                          color: AppTheme.blue,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                assignment.code,
                                style: const TextStyle(
                                  color: AppTheme.blueDark,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${assignment.displayPackageType} · ${assignment.stateName} · ${assignment.formattedDate}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Toca para ver destinatario y dirección',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: AppTheme.blue,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (deliveringAssignmentId == assignment.assignmentId)
                          const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: AppTheme.blue,
                            ),
                          )
                        else
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: AppTheme.blue,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AssignmentDetailRow extends StatelessWidget {
  const _AssignmentDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.blue, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  value,
                  style: const TextStyle(
                    color: AppTheme.blueDark,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
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

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return AppSoftCard(
      padding: const EdgeInsets.all(16),
      backgroundColor: AppTheme.yellowField,
      child: Row(
        children: [
          Icon(icon, color: AppTheme.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(message),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
