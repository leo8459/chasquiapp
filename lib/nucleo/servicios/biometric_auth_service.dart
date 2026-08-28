import 'package:local_auth/local_auth.dart';

class BiometricAuthService {
  BiometricAuthService({LocalAuthentication? localAuth})
    : _localAuth = localAuth ?? LocalAuthentication();

  final LocalAuthentication _localAuth;
  static const Duration _availabilityCacheTtl = Duration(minutes: 2);
  bool? _availabilityCache;
  DateTime? _availabilityCacheAt;

  bool _isCacheFresh() {
    final cachedAt = _availabilityCacheAt;
    if (cachedAt == null) return false;
    return DateTime.now().difference(cachedAt) <= _availabilityCacheTtl;
  }

  Future<bool> isAvailable() async {
    if (_availabilityCache != null && _isCacheFresh()) {
      return _availabilityCache!;
    }
    try {
      final supportsDevice = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!supportsDevice || !canCheck) {
        _cacheAvailability(false);
        return false;
      }
      final methods = await _localAuth.getAvailableBiometrics();
      final available = methods.isNotEmpty;
      _cacheAvailability(available);
      return available;
    } catch (_) {
      _cacheAvailability(false);
      return false;
    }
  }

  Future<bool> authenticate() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Confirma tu identidad para ingresar',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  void _cacheAvailability(bool available) {
    _availabilityCache = available;
    _availabilityCacheAt = DateTime.now();
  }
}
