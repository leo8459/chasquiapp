import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:scan_agbc/nucleo/componentes/app_cards.dart';
import 'package:scan_agbc/nucleo/componentes/app_feedback_banner.dart';
import 'package:scan_agbc/nucleo/componentes/app_page_scaffold.dart';
import 'package:scan_agbc/nucleo/tema/app_theme.dart';
import 'package:scan_agbc/nucleo/utilidades/user_friendly_error_mapper.dart';
import 'package:scan_agbc/funcionalidades/cartero/presentacion/paginas/delivery_photo_capture_page.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/modelos/assigned_package_summary.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/repositorios/package_tracking_repository.dart';
import 'package:scan_agbc/funcionalidades/operaciones_postales/dominio/utilidades/delivery_recipient_name_validator.dart';

class SiopPackageDeliveryPage extends StatefulWidget {
  const SiopPackageDeliveryPage({
    super.key,
    required this.assignment,
    required this.repository,
  });

  final AssignedPackageSummary assignment;
  final PackageTrackingRepository repository;

  @override
  State<SiopPackageDeliveryPage> createState() =>
      _SiopPackageDeliveryPageState();
}

class _SiopPackageDeliveryPageState extends State<SiopPackageDeliveryPage> {
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _receivedByController = TextEditingController();
  final FocusNode _receivedByFocusNode = FocusNode();
  DateTime _deliveredAt = DateTime.now();
  DeliveryPhotoCaptureResult? _deliveryPhoto;
  bool _saving = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    _receivedByController.dispose();
    _receivedByFocusNode.dispose();
    super.dispose();
  }

  Future<void> _capturePhoto() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    final photo = await Navigator.of(context).push<DeliveryPhotoCaptureResult>(
      MaterialPageRoute(builder: (_) => const DeliveryPhotoCapturePage()),
    );
    if (!mounted || photo == null || photo.bytes.isEmpty) return;
    setState(() => _deliveryPhoto = photo);
  }

  Future<void> _selectDeliveryDateTime() async {
    if (_saving) return;
    final now = DateTime.now();
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _deliveredAt.isAfter(now) ? now : _deliveredAt,
      firstDate: DateTime(2020),
      lastDate: now,
      helpText: 'Fecha de entrega',
    );
    if (!mounted || selectedDate == null) return;

    final selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_deliveredAt),
      helpText: 'Hora de entrega',
    );
    if (!mounted || selectedTime == null) return;

    final selected = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );
    if (selected.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      showAppFeedbackBanner(
        context,
        'La fecha de entrega no puede estar en el futuro.',
        tone: AppFeedbackTone.error,
      );
      return;
    }
    setState(() => _deliveredAt = selected);
  }

  Future<void> _submit() async {
    if (_saving) return;
    final receivedByValidation = DeliveryRecipientNameValidator.validate(
      _receivedByController.text,
    );
    if (!receivedByValidation.isValid) {
      showAppFeedbackBanner(
        context,
        receivedByValidation.errorMessage ??
            'Escribe el nombre de quien recibio el paquete.',
        tone: AppFeedbackTone.error,
      );
      _receivedByFocusNode.requestFocus();
      return;
    }

    final photo = _deliveryPhoto;
    if (photo == null || photo.bytes.isEmpty) {
      showAppFeedbackBanner(
        context,
        'Debes tomar o elegir una foto de la entrega.',
        tone: AppFeedbackTone.error,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar entrega'),
        content: Text(
          'Se registrara ${widget.assignment.code} como entregado en BoliPost con la foto adjunta.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirmar entrega'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      await widget.repository.deliverMySiopPackage(
        code: widget.assignment.code,
        description: _descriptionController.text,
        receivedBy: receivedByValidation.normalizedValue,
        deliveredAt: _deliveredAt,
        deliveryPhotoBytes: photo.bytes,
        deliveryPhotoFileName:
            'entrega_${widget.assignment.code}_$timestamp.${photo.fileExtension}',
        deliveryPhotoContentType: photo.contentType,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      showAppFeedbackBanner(
        context,
        UserFriendlyErrorMapper.message(
          error,
          fallback: 'No pudimos confirmar la entrega en BoliPost.',
        ),
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatDateTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final photo = _deliveryPhoto;
    return AppPageScaffold(
      title: 'Entregar paquete',
      resizeToAvoidBottomInset: true,
      body: ListView(
        padding: AppTheme.pagePadding,
        children: [
          AppSectionIntroCard(
            title: widget.assignment.code,
            subtitle:
                '${widget.assignment.displayPackageType} · ${widget.assignment.recipientName.isEmpty ? 'Sin destinatario' : widget.assignment.recipientName}',
            icon: Icons.local_shipping_rounded,
          ),
          const SizedBox(height: 16),
          AppPanelCard(
            padding: const EdgeInsets.all(18),
            backgroundColor: AppTheme.yellowField,
            borderColor: AppTheme.softBorder,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _descriptionController,
                  enabled: !_saving,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                    labelText: 'Descripcion (opcional)',
                    hintText: 'Observaciones sobre la entrega',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _receivedByController,
                  focusNode: _receivedByFocusNode,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Recibido por *',
                    hintText: 'Nombre completo',
                    prefixIcon: Icon(Icons.person_rounded),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _selectDeliveryDateTime,
                  icon: const Icon(Icons.calendar_month_rounded),
                  label: Text('Fecha y hora: ${_formatDateTime(_deliveredAt)}'),
                ),
                const SizedBox(height: 16),
                _DeliveryPhotoField(
                  photoBytes: photo?.bytes,
                  enabled: !_saving,
                  onPressed: _capturePhoto,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_rounded),
                  label: Text(
                    _saving ? 'Enviando entrega...' : 'Confirmar entrega',
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

class _DeliveryPhotoField extends StatelessWidget {
  const _DeliveryPhotoField({
    required this.photoBytes,
    required this.enabled,
    required this.onPressed,
  });

  final Uint8List? photoBytes;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoBytes != null && photoBytes!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Foto de entrega *',
          style: TextStyle(
            color: AppTheme.blueDark,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        if (hasPhoto)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.memory(
              photoBytes!,
              height: 220,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          ),
        if (hasPhoto) const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: enabled ? onPressed : null,
          icon: Icon(
            hasPhoto ? Icons.cameraswitch_rounded : Icons.camera_alt_rounded,
          ),
          label: Text(
            hasPhoto ? 'Cambiar foto' : 'Tomar foto o elegir de galeria',
          ),
        ),
        const Text(
          'La foto es obligatoria y se enviara como evidencia a BoliPost.',
          style: TextStyle(color: AppTheme.blueMid, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
