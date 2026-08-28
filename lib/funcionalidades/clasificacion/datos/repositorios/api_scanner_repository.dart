import 'dart:convert';

import 'package:scan_agbc/nucleo/red/api_client.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/dominio/modelos/scan_result.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/dominio/modelos/ventanilla_option.dart';
import 'package:scan_agbc/funcionalidades/clasificacion/dominio/repositorios/scanner_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiScannerRepository implements ScanRepository {
  ApiScannerRepository(this._client);

  final ApiClient _client;
  static const _ventanillasCacheKey = 'scanner_ventanillas_cache';
  static const _ventanillasCacheSavedAtKey = 'scanner_ventanillas_saved_at';
  static const _ventanillasCacheTtl = Duration(hours: 12);

  List<VentanillaOption>? _memoryCachedVentanillas;
  DateTime? _memoryCachedVentanillasAt;

  void clearMemoryCache() {
    _memoryCachedVentanillas = null;
    _memoryCachedVentanillasAt = null;
  }

  @override
  Future<void> saveScan(ScanResult result) async {
    try {
      await _client.postJsonMap(
        '/mobile/scanner/scans',
        authorize: true,
        body: {
          'barcode_text': result.barcodeText,
          'nombre': result.nombre,
          'telefono': result.telefono,
          'peso': result.peso,
          'ciudad': result.ciudad,
          'zona': result.zona,
          'aduana': result.aduana,
          'ventanilla_id': result.ventanillaId,
          'ventanilla_nombre': result.ventanillaNombre,
          'tipo_documento': result.tipoDocumento,
          'observaciones': result.observaciones,
          'created_at': result.createdAt.toUtc().toIso8601String(),
        },
      );
    } on ApiException catch (error) {
      if (error.code != null && error.code!.trim().isNotEmpty) {
        throw StateError(error.code!);
      }
      throw StateError(error.message);
    }
  }

  @override
  Future<List<VentanillaOption>> getVentanillas() async {
    final memoryCached = _readFreshMemoryCachedVentanillas();
    if (memoryCached != null) {
      return memoryCached;
    }

    final cachedOnDisk = await _readCachedVentanillasFromDisk();
    if (cachedOnDisk.isNotEmpty) {
      _saveMemoryCachedVentanillas(cachedOnDisk);
      return cachedOnDisk;
    }

    try {
      final payload = await _client.getJsonMap(
        '/mobile/scanner/ventanillas',
        authorize: true,
      );
      final items = payload['ventanillas'];
      if (items is! List) {
        return const <VentanillaOption>[
          VentanillaOption(id: 1, label: 'Ventanilla 1'),
        ];
      }

      final options = items
          .map((item) => _mapVentanilla(item))
          .whereType<VentanillaOption>()
          .toList();
      if (options.isEmpty) {
        return const <VentanillaOption>[
          VentanillaOption(id: 1, label: 'Ventanilla 1'),
        ];
      }

      _saveMemoryCachedVentanillas(options);
      await _writeCachedVentanillasToDisk(options);
      return options;
    } on ApiException catch (error) {
      final staleCached = await _readCachedVentanillasFromDisk(
        allowExpired: true,
      );
      if (staleCached.isNotEmpty) {
        _saveMemoryCachedVentanillas(staleCached);
        return staleCached;
      }
      throw StateError(error.message);
    }
  }

  List<VentanillaOption>? _readFreshMemoryCachedVentanillas() {
    final cached = _memoryCachedVentanillas;
    final cachedAt = _memoryCachedVentanillasAt;
    if (cached == null || cachedAt == null || cached.isEmpty) {
      return null;
    }
    if (DateTime.now().difference(cachedAt) > _ventanillasCacheTtl) {
      return null;
    }
    return List<VentanillaOption>.unmodifiable(cached);
  }

  void _saveMemoryCachedVentanillas(List<VentanillaOption> options) {
    _memoryCachedVentanillas = List<VentanillaOption>.unmodifiable(options);
    _memoryCachedVentanillasAt = DateTime.now();
  }

  Future<List<VentanillaOption>> _readCachedVentanillasFromDisk({
    bool allowExpired = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final rawItems = prefs.getString(_ventanillasCacheKey);
    final rawSavedAt = prefs.getString(_ventanillasCacheSavedAtKey);
    if ((rawItems ?? '').trim().isEmpty || (rawSavedAt ?? '').trim().isEmpty) {
      return const <VentanillaOption>[];
    }

    final savedAt = DateTime.tryParse(rawSavedAt!);
    if (!allowExpired &&
        (savedAt == null ||
            DateTime.now().difference(savedAt) > _ventanillasCacheTtl)) {
      return const <VentanillaOption>[];
    }

    try {
      final decoded = jsonDecode(rawItems!);
      if (decoded is! List) {
        return const <VentanillaOption>[];
      }

      return decoded
          .map((item) => _mapVentanilla(item))
          .whereType<VentanillaOption>()
          .toList(growable: false);
    } catch (_) {
      return const <VentanillaOption>[];
    }
  }

  Future<void> _writeCachedVentanillasToDisk(
    List<VentanillaOption> options,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      options
          .map(
            (option) => <String, dynamic>{
              'id': option.id,
              'label': option.label,
            },
          )
          .toList(growable: false),
    );
    await prefs.setString(_ventanillasCacheKey, encoded);
    await prefs.setString(
      _ventanillasCacheSavedAtKey,
      DateTime.now().toIso8601String(),
    );
  }

  VentanillaOption? _mapVentanilla(dynamic item) {
    if (item is! Map) {
      return null;
    }

    final id = _toInt(item['id']);
    final label = item['label']?.toString().trim() ?? '';
    if (id <= 0) {
      return null;
    }

    return VentanillaOption(
      id: id,
      label: label.isEmpty ? 'VENTANILLA $id' : label,
    );
  }

  int _toInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  /// Removes all local cache entries used by this repository.
  /// Call this on logout to prevent stale or leaked data.
  static Future<void> clearLocalCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_ventanillasCacheKey);
      await prefs.remove(_ventanillasCacheSavedAtKey);
    } catch (_) {
      // Best-effort cleanup; failures are not critical.
    }
  }
}
