import 'dart:async';

import 'package:flutter/material.dart';

import 'package:scan_agbc/nucleo/inyeccion/app_services.dart';
import 'package:scan_agbc/nucleo/tema/app_theme.dart';
import 'package:scan_agbc/nucleo/utilidades/user_friendly_error_mapper.dart';
import 'package:scan_agbc/nucleo/componentes/app_cards.dart';
import 'package:scan_agbc/nucleo/componentes/app_page_scaffold.dart';
import 'package:scan_agbc/funcionalidades/autenticacion/dominio/modelos/authenticated_user.dart';
import 'package:scan_agbc/funcionalidades/autenticacion/dominio/utilidades/user_role_permissions.dart';
import 'package:scan_agbc/funcionalidades/inicio/presentacion/paginas/home_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.services});

  final AppServices services;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  final ValueNotifier<bool> _obscurePassword = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _submitting = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _bootstrapping = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _authenticatingBiometric = ValueNotifier<bool>(
    false,
  );
  final ValueNotifier<bool> _biometricAvailable = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _biometricEnabledSetting = ValueNotifier<bool>(
    false,
  );

  late final _sessionSecurityService = widget.services.sessionSecurityService;
  late final _biometricAuthService = widget.services.biometricAuthService;
  late final _authRepository = widget.services.authRepository;
  late final Listenable _biometricUiListenable;

  String? _savedUser;
  bool _rememberSessionEnabled = false;
  int _biometricLookupRequestId = 0;
  bool _navigatingToHome = false;

  @override
  void initState() {
    super.initState();
    _biometricUiListenable = Listenable.merge([
      _submitting,
      _bootstrapping,
      _authenticatingBiometric,
      _biometricAvailable,
      _biometricEnabledSetting,
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bootstrapSecurityFlow();
    });
  }

  @override
  void dispose() {
    _userController.dispose();
    _passwordController.dispose();
    _obscurePassword.dispose();
    _submitting.dispose();
    _bootstrapping.dispose();
    _authenticatingBiometric.dispose();
    _biometricAvailable.dispose();
    _biometricEnabledSetting.dispose();
    super.dispose();
  }

  Future<void> _bootstrapSecurityFlow() async {
    String? savedUser;
    List<String> knownAccounts = const <String>[];
    var rememberSessionEnabled = false;

    try {
      final securityResults = await Future.wait<Object?>([
        _sessionSecurityService.isRememberSessionEnabled(),
        _sessionSecurityService.readSessionEmail(),
        _sessionSecurityService.readKnownAccounts(),
        _biometricAuthService.isAvailable(),
      ]);
      rememberSessionEnabled = securityResults[0] as bool;
      savedUser = securityResults[1] as String?;
      knownAccounts = securityResults[2] as List<String>;
      _biometricAvailable.value = securityResults[3] as bool;
    } catch (_) {
      savedUser = null;
      knownAccounts = const <String>[];
      rememberSessionEnabled = false;
      _biometricAvailable.value = false;
    }

    if (!mounted) return;

    final preferredEmail = (() {
      final remembered = savedUser?.trim().toLowerCase() ?? '';
      if (remembered.isNotEmpty) return remembered;
      if (knownAccounts.isEmpty) return null;
      final latestKnown = knownAccounts.first.trim().toLowerCase();
      return latestKnown.isEmpty ? null : latestKnown;
    })();

    setState(() {
      _rememberSessionEnabled = rememberSessionEnabled;
      _savedUser = preferredEmail;
    });
    _biometricEnabledSetting.value = false;

    if (preferredEmail != null && _userController.text.trim().isEmpty) {
      _userController.text = preferredEmail;
    }

    _handleUserInputChanged();

    if (mounted) {
      _bootstrapping.value = false;
    }
  }

  void _handleUserInputChanged() {
    final currentEmail = _userController.text.trim().toLowerCase();

    if (currentEmail.isEmpty) {
      _savedUser = null;
      _biometricEnabledSetting.value = false;
      return;
    }

    _savedUser = currentEmail;
    _biometricEnabledSetting.value = false;
    _loadBiometricEligibilityFor(currentEmail);
  }

  Future<void> _loadBiometricEligibilityFor(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) {
      _biometricEnabledSetting.value = false;
      return;
    }

    final requestId = ++_biometricLookupRequestId;
    final enabledForAccount = await _sessionSecurityService
        .isBiometricEnabledFor(normalizedEmail);
    if (!mounted || requestId != _biometricLookupRequestId) return;

    _biometricEnabledSetting.value =
        _rememberSessionEnabled &&
        _biometricAvailable.value &&
        enabledForAccount;
  }

  Future<void> _tryBiometricLogin() async {
    if (_savedUser == null || _navigatingToHome) return;

    _authenticatingBiometric.value = true;
    var authenticated = false;
    try {
      final available = await _biometricAuthService.isAvailable();
      if (!mounted) return;
      _biometricAvailable.value = available;
      if (available) {
        authenticated = await _biometricAuthService.authenticate();
      }
    } finally {
      if (mounted) {
        _authenticatingBiometric.value = false;
      }
    }

    if (!mounted || _navigatingToHome) return;

    if (authenticated) {
      try {
        final authorizedUser = await _authRepository.authorizeRememberedAccount(
          _savedUser!,
        );
        await _sessionSecurityService.saveLastAuthAt(DateTime.now());
        if (!mounted || _navigatingToHome) return;
        _goToHome(authorizedUser);
        return;
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_mapAuthError(error))));
        _bootstrapping.value = false;
        return;
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo autenticar con huella.')),
    );
    _bootstrapping.value = false;
  }

  void _submit() {
    unawaited(_submitAsync());
  }

  Future<void> _submitAsync() async {
    if (!_formKey.currentState!.validate()) return;
    if (_submitting.value) return;

    final email = _userController.text.trim().toLowerCase();
    final password = _passwordController.text;

    _submitting.value = true;
    FocusScope.of(context).unfocus();

    try {
      final authenticatedUser = await _authRepository.signIn(
        email: email,
        password: password,
      );
      final rememberSessionEnabled = await _sessionSecurityService
          .isRememberSessionEnabled();

      if (rememberSessionEnabled) {
        await Future.wait([
          _sessionSecurityService.saveSessionEmail(authenticatedUser.email),
          widget.services.persistRememberedAuthState(authenticatedUser),
        ]);
        _savedUser = authenticatedUser.email;
      } else {
        await _sessionSecurityService.clearSession();
        await _sessionSecurityService.saveKnownAccount(authenticatedUser.email);
      }
      await _sessionSecurityService.saveLastAuthAt(DateTime.now());

      if (!mounted) return;
      _goToHome(authenticatedUser);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_mapAuthError(error))));
    } finally {
      if (mounted) {
        _submitting.value = false;
      }
    }
  }

  void _goToHome(AuthenticatedUser user) {
    if (_navigatingToHome) return;
    _navigatingToHome = true;
    final area = _resolveArea(user);
    Navigator.of(context)
        .pushReplacement(
          MaterialPageRoute(
            builder: (_) => HomePage(
              currentUser: user,
              services: widget.services,
              area: area,
            ),
          ),
        )
        .then((_) {
          _navigatingToHome = false;
        });
  }

  UserArea _resolveArea(AuthenticatedUser user) {
    final permissions = UserRolePermissions.fromRoles(user.roles);
    if (permissions.isAdministrator) {
      return UserArea.modeSelection;
    }
    if (permissions.canChooseOperationalMode) {
      return UserArea.modeSelection;
    }
    return switch (permissions.accessProfile) {
      UserRoleAccessProfile.clasificaciones => UserArea.clasificaciones,
      UserRoleAccessProfile.carteros => UserArea.carteros,
      UserRoleAccessProfile.gestion => UserArea.gestion,
      UserRoleAccessProfile.consulta => UserArea.consulta,
    };
  }

  static const String _institutionalDomain = '@correos.gob.bo';
  static final RegExp _institutionalUserPattern = RegExp(
    r'^[a-z0-9]+(?:[._+-][a-z0-9]+)*$',
  );

  String? _validateUser(String? value) {
    final text = value?.trim().toLowerCase() ?? '';
    if (text.isEmpty) return 'Ingrese su usuario';

    if (!text.endsWith(_institutionalDomain)) {
      return 'Use su correo institucional @correos.gob.bo';
    }

    final localPart = text.substring(
      0,
      text.length - _institutionalDomain.length,
    );
    if (!_institutionalUserPattern.hasMatch(localPart)) {
      return 'Ingrese un correo institucional válido.';
    }

    return null;
  }

  String? _validatePassword(String? value) {
    if ((value ?? '').trim().isEmpty) return 'Ingrese su contraseña';
    return null;
  }

  String _mapAuthError(Object error) {
    return UserFriendlyErrorMapper.message(
      error,
      fallback: 'No pudimos iniciar tu sesión. Intenta nuevamente.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      resizeToAvoidBottomInset: false,
      safeAreaTop: true,
      backgroundDecoration: AppTheme.loginPageDecoration,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxHeight < 700;
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: AppPanelCard(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    isCompact ? 26 : 32,
                    24,
                    isCompact ? 22 : 28,
                  ),
                  backgroundColor: AppTheme.yellowSoft,
                  borderRadius: const BorderRadius.all(Radius.circular(32)),
                  borderColor: AppTheme.blue,
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x331B305F),
                      blurRadius: 28,
                      offset: Offset(0, 14),
                    ),
                  ],
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _Header(),
                        const SizedBox(height: 28),
                        const _FieldLabel(text: 'Correo Institucional'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _userController,
                          onChanged: (_) => _handleUserInputChanged(),
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          cursorColor: AppTheme.yellow,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: AppTheme.blue, fontSize: 15),
                          decoration: const InputDecoration(
                            hintText: 'usuario@correos.gob.bo',
                            prefixIcon: Icon(Icons.alternate_email_rounded),
                          ),
                          validator: _validateUser,
                        ),
                        const SizedBox(height: 16),
                        const _FieldLabel(text: 'Contraseña'),
                        const SizedBox(height: 8),
                        ValueListenableBuilder<bool>(
                          valueListenable: _obscurePassword,
                          builder: (context, obscurePassword, _) {
                            return AnimatedBuilder(
                              animation: _biometricUiListenable,
                              builder: (context, _) {
                                final canUseQuickBiometric =
                                    _savedUser != null &&
                                    _biometricAvailable.value &&
                                    _biometricEnabledSetting.value;
                                final authenticating =
                                    _authenticatingBiometric.value;
                                final bootstrapping = _bootstrapping.value;
                                return Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _passwordController,
                                        obscureText: obscurePassword,
                                        textInputAction: TextInputAction.done,
                                        onFieldSubmitted: (_) => _submit(),
                                        cursorColor: AppTheme.yellow,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyLarge
                                            ?.copyWith(
                                              color: AppTheme.blue,
                                              fontSize: 15,
                                            ),
                                        decoration: InputDecoration(
                                          hintText: 'Ingrese su contraseña',
                                          prefixIcon: const Icon(
                                            Icons.lock_outline_rounded,
                                          ),
                                          suffixIcon: IconButton(
                                            splashRadius: 20,
                                            onPressed: () {
                                              _obscurePassword.value =
                                                  !_obscurePassword.value;
                                            },
                                            icon: Icon(
                                              obscurePassword
                                                  ? Icons.visibility_off_rounded
                                                  : Icons.visibility_rounded,
                                              color: AppTheme.yellow,
                                            ),
                                          ),
                                        ),
                                        validator: _validatePassword,
                                      ),
                                    ),
                                    if (canUseQuickBiometric) ...[
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 56,
                                        height: 56,
                                        child: Tooltip(
                                          message: 'Ingresar con huella',
                                          child: OutlinedButton(
                                            onPressed:
                                                authenticating || bootstrapping
                                                ? null
                                                : _tryBiometricLogin,
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: AppTheme.blue,
                                              side: const BorderSide(
                                                color: AppTheme.blue,
                                                width: 1.2,
                                              ),
                                              backgroundColor:
                                                  AppTheme.yellowField,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    AppTheme.radiusPill,
                                              ),
                                              padding: EdgeInsets.zero,
                                            ),
                                            child: authenticating
                                                ? const SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2.2,
                                                          color: AppTheme.blue,
                                                        ),
                                                  )
                                                : const Icon(
                                                    Icons.fingerprint_rounded,
                                                    size: 26,
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 22),
                        ValueListenableBuilder<bool>(
                          valueListenable: _submitting,
                          builder: (context, submitting, _) {
                            return DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Color(0xFFFAD35D), AppTheme.yellow],
                                ),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x33D8A824),
                                    blurRadius: 18,
                                    offset: Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: ElevatedButton.icon(
                                onPressed: submitting ? null : _submit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  foregroundColor: AppTheme.blue,
                                ),
                                icon: submitting
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: AppTheme.blue,
                                        ),
                                      )
                                    : const Icon(Icons.login_rounded, size: 22),
                                label: Text(
                                  submitting
                                      ? 'Ingresando...'
                                      : 'Iniciar sesión',
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.center,
                          child: Text(
                            'Acceso a ScanAGBC',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AppTheme.blueDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.yellow,
            borderRadius: AppTheme.radiusPill,
            border: Border.all(color: AppTheme.blue, width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.markunread_outlined,
                color: AppTheme.blue,
                size: 18,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'AGENCIA BOLIVIANA DE CORREOS',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelSmall?.copyWith(
                    color: AppTheme.blue,
                    fontSize: 12,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Bienvenido',
          style: textTheme.headlineSmall?.copyWith(
            color: AppTheme.blue,
            height: 1.05,
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.labelMedium?.copyWith(color: AppTheme.blue),
    );
  }
}
