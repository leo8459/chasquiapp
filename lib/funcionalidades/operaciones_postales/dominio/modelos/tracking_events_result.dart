import 'package:scan_agbc/nucleo/utilidades/bolivia_date_time_formatter.dart';

class TrackingEventsResult {
  const TrackingEventsResult({
    required this.code,
    required this.table,
    required this.exact,
    required this.limit,
    required this.total,
    required this.events,
  });

  final String code;
  final String table;
  final bool exact;
  final int limit;
  final int total;
  final List<TrackingEventSummary> events;

  bool get hasEvents => events.isNotEmpty;

  String get safeCode => code.trim().isEmpty ? 'Sin código' : code.trim();

  String get serviceLabel {
    final normalizedTable = table.trim().toLowerCase();
    switch (normalizedTable) {
      case 'eventos_ems':
        return 'EMS';
      case 'eventos_certi':
        return 'Certificado';
      case 'eventos_contrato':
        return 'Contrato';
      case 'eventos_ordi':
        return 'Ordinario';
      case 'eventos_solicitud':
        return 'Solicitud';
      default:
        return 'Todos';
    }
  }
}

class TrackingEventSummary {
  const TrackingEventSummary({
    required this.table,
    required this.service,
    required this.id,
    required this.code,
    required this.eventId,
    required this.event,
    required this.detail,
    required this.userId,
    required this.user,
    required this.createdAt,
    required this.photo,
  });

  final String table;
  final String service;
  final int id;
  final String code;
  final int eventId;
  final String event;
  final String detail;
  final int userId;
  final String user;
  final String createdAt;
  final String photo;

  String get safeService => service.trim().isEmpty ? 'SIOP' : service.trim();

  String get safeEvent => event.trim().isEmpty ? 'Sin evento' : event.trim();

  String get safeDetail => detail.trim();

  String get safeUser => user.trim().isEmpty ? 'Sin usuario' : user.trim();

  String get safeCreatedAt {
    final normalized = createdAt.trim();
    if (normalized.isEmpty) return 'Sin fecha';
    return BoliviaDateTimeFormatter.format(DateTime.tryParse(normalized));
  }
}
