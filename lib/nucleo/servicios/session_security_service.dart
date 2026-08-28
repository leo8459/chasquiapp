import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionSecurityService {
  SessionSecurityService({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  static const _sessionEmailKey = 'session_email';
  static const _knownAccountsKey = 'known_accounts';
  static const _rememberSessionKey = 'remember_session';
  static const _biometricAccountsKey = 'biometric_enabled_accounts';
  static const _lastAuthAtKey = 'last_auth_at';
  static const _apiAccessTokenKey = 'api_access_token';
  static const _authenticatedUserPayloadKey = 'authenticated_user_payload';
  static const _packageTrackingAssignmentsCachePrefix =
      'package_tracking_assignments_cache_v1';
  static const _packageTrackingInventoryCachePrefix =
      'package_tracking_inventory_cache_v1';
  static const _scannerVentanillasCacheKey = 'scanner_ventanillas_cache';
  static const _scannerVentanillasCacheSavedAtKey =
      'scanner_ventanillas_saved_at';

  final FlutterSecureStorage _storage;

  Future<String?> readSessionEmail() {
    return _storage.read(key: _sessionEmailKey);
  }

  Future<void> saveSessionEmail(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) return;
    await _storage.write(key: _sessionEmailKey, value: normalizedEmail);
    await saveKnownAccount(normalizedEmail);
  }

  Future<void> clearSession() async {
    await clearAuthenticatedState();
  }

  Future<void> clearAuthenticatedState({
    bool preserveRememberedAccount = false,
  }) async {
    String? rememberedEmail;
    var rememberEnabled = false;

    if (preserveRememberedAccount) {
      final rememberedState = await Future.wait<Object?>([
        isRememberSessionEnabled(),
        readSessionEmail(),
      ]);
      rememberEnabled = rememberedState[0] as bool;
      if (rememberEnabled) {
        rememberedEmail = rememberedState[1] as String?;
      }
    }

    await Future.wait([
      _storage.delete(key: _sessionEmailKey),
      _storage.delete(key: _lastAuthAtKey),
      _storage.delete(key: _apiAccessTokenKey),
      _storage.delete(key: _authenticatedUserPayloadKey),
      clearCachedOperationalData(),
    ]);

    if (preserveRememberedAccount &&
        rememberEnabled &&
        rememberedEmail != null &&
        rememberedEmail.trim().isNotEmpty) {
      await Future.wait([
        _storage.write(
          key: _sessionEmailKey,
          value: rememberedEmail.trim().toLowerCase(),
        ),
        _storage.write(key: _rememberSessionKey, value: 'true'),
      ]);
      return;
    }

    await _storage.write(key: _rememberSessionKey, value: 'false');
  }

  Future<bool> isRememberSessionEnabled() async {
    final value = await _storage.read(key: _rememberSessionKey);
    return value == 'true';
  }

  Future<void> setRememberSessionEnabled(bool enabled) {
    return _storage.write(
      key: _rememberSessionKey,
      value: enabled ? 'true' : 'false',
    );
  }

  Future<bool> isBiometricEnabledFor(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) return false;
    final accounts = await _readBiometricAccounts();
    return accounts.contains(normalizedEmail);
  }

  Future<void> setBiometricEnabledFor(String email, bool enabled) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) return;

    final accounts = await _readBiometricAccounts();
    if (enabled) {
      accounts.add(normalizedEmail);
    } else {
      accounts.remove(normalizedEmail);
    }
    await _storage.write(key: _biometricAccountsKey, value: accounts.join('|'));
  }

  Future<Set<String>> _readBiometricAccounts() async {
    final raw = (await _storage.read(key: _biometricAccountsKey) ?? '').trim();
    if (raw.isEmpty) return <String>{};
    return raw
        .split('|')
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toSet();
  }

  Future<List<String>> readKnownAccounts() async {
    final raw = (await _storage.read(key: _knownAccountsKey) ?? '').trim();
    if (raw.isEmpty) return <String>[];

    final unique = <String>{};
    final ordered = <String>[];
    for (final item in raw.split('|')) {
      final email = item.trim().toLowerCase();
      if (email.isEmpty) continue;
      if (unique.add(email)) {
        ordered.add(email);
      }
    }
    return List<String>.of(ordered);
  }

  Future<void> saveKnownAccount(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) return;

    final accounts = await readKnownAccounts();
    accounts.removeWhere((item) => item == normalizedEmail);
    accounts.insert(0, normalizedEmail);
    final limited = accounts.take(20).toList();

    await _storage.write(key: _knownAccountsKey, value: limited.join('|'));
  }

  Future<DateTime?> readLastAuthAt() async {
    final value = await _storage.read(key: _lastAuthAtKey);
    if (value == null || value.trim().isEmpty) return null;
    return DateTime.tryParse(value);
  }

  Future<void> saveLastAuthAt(DateTime time) {
    return _storage.write(
      key: _lastAuthAtKey,
      value: time.toUtc().toIso8601String(),
    );
  }

  Future<String?> readApiAccessToken() {
    return _storage.read(key: _apiAccessTokenKey);
  }

  Future<void> saveApiAccessToken(String token) async {
    final normalized = token.trim();
    if (normalized.isEmpty) return;
    await _storage.write(key: _apiAccessTokenKey, value: normalized);
  }

  Future<String?> readAuthenticatedUserPayload() {
    return _storage.read(key: _authenticatedUserPayloadKey);
  }

  Future<void> saveAuthenticatedUserPayload(String payload) async {
    final normalized = payload.trim();
    if (normalized.isEmpty) return;
    await _storage.write(key: _authenticatedUserPayloadKey, value: normalized);
  }

  Future<void> saveAuthenticatedState({
    required String token,
    required String userPayload,
  }) async {
    await Future.wait([
      saveApiAccessToken(token),
      saveAuthenticatedUserPayload(userPayload),
    ]);
  }

  Future<void> clearCachedOperationalData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keysToRemove = prefs
          .getKeys()
          .where(
            (key) =>
                key.startsWith(_packageTrackingAssignmentsCachePrefix) ||
                key.startsWith(_packageTrackingInventoryCachePrefix) ||
                key == _scannerVentanillasCacheKey ||
                key == _scannerVentanillasCacheSavedAtKey,
          )
          .toList(growable: false);

      await Future.wait(keysToRemove.map(prefs.remove));
    } catch (_) {
      // Session cleanup should continue even if local cache cleanup fails.
    }
  }
}
