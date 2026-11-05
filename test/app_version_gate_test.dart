import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:scan_agbc/nucleo/componentes/app_version_gate.dart';
import 'package:scan_agbc/nucleo/configuracion/api_config.dart';
import 'package:scan_agbc/nucleo/red/api_client.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient()
    : super(config: const ApiConfig(baseUrl: 'https://example.test/api/'));

  String requiredVersion = '1.0.5+6';
  String downloadUrl = 'https://example.test/descargas/';
  bool offline = false;

  @override
  Future<Map<String, dynamic>> getJsonMap(
    String path, {
    Map<String, String?>? queryParameters,
    bool authorize = false,
  }) async {
    if (offline) throw const ApiException(message: 'offline');
    return {'required_version': requiredVersion, 'download_url': downloadUrl};
  }
}

void main() {
  const launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcherChannel, null);
  });
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'ChasquiApp',
      packageName: 'com.agbc.scanagbc',
      version: '1.0.5',
      buildNumber: '6',
      buildSignature: '',
    );
  });

  Future<void> openGate(WidgetTester tester, _FakeApiClient client) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AppVersionGate(client: client, child: child!),
        home: const Scaffold(body: Text('Formulario de login')),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('la versión exacta permite acceder al login', (tester) async {
    await openGate(tester, _FakeApiClient());
    expect(find.text('Formulario de login'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('descargar abre el enlace externo y mantiene el bloqueo', (
    tester,
  ) async {
    MethodCall? launchCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcherChannel, (call) async {
          launchCall = call;
          return true;
        });
    await openGate(tester, _FakeApiClient()..requiredVersion = '1.0.6+7');
    await tester.tap(find.text('Descargar actualización'));
    await tester.pumpAndSettle();
    expect(launchCall?.method, 'launch');
    expect(launchCall?.arguments['url'], 'https://example.test/descargas/');
    expect(launchCall?.arguments['useWebView'], false);
    expect(find.text('Actualización obligatoria'), findsOneWidget);
  });

  testWidgets('volver del segundo plano comprueba nuevamente la versión', (
    tester,
  ) async {
    final client = _FakeApiClient();
    await openGate(tester, client);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    client.requiredVersion = '1.0.6+7';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Actualización obligatoria'), findsOneWidget);
  });

  testWidgets('una política inválida no habilita el ingreso', (tester) async {
    await openGate(
      tester,
      _FakeApiClient()..downloadUrl = 'javascript:alert(1)',
    );
    expect(find.text('Formulario de login'), findsNothing);
    expect(find.text('No se pudo comprobar la versión'), findsOneWidget);
  });

  testWidgets('otro build bloquea el ingreso y no permite cerrar el modal', (
    tester,
  ) async {
    await openGate(tester, _FakeApiClient()..requiredVersion = '1.0.5+7');
    expect(find.text('Formulario de login'), findsNothing);
    expect(find.text('Actualización obligatoria'), findsOneWidget);
    expect(find.text('Descargar actualización'), findsOneWidget);
    expect(find.text('https://example.test/descargas/'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Actualización obligatoria'), findsOneWidget);
  });

  testWidgets('sin red bloquea el ingreso y permite reintentar', (
    tester,
  ) async {
    final client = _FakeApiClient()..offline = true;
    await openGate(tester, client);
    expect(find.text('Formulario de login'), findsNothing);
    expect(find.text('No se pudo comprobar la versión'), findsOneWidget);
    client.offline = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Formulario de login'), findsOneWidget);
  });

  testWidgets('un rechazo del servidor bloquea también una sesión abierta', (
    tester,
  ) async {
    final client = _FakeApiClient();
    await openGate(tester, client);
    client.requiredUpdate.value = {
      'required_version': '1.0.6+7',
      'download_url': 'https://example.test/descargas/',
    };
    await tester.pumpAndSettle();
    expect(find.text('Actualización obligatoria'), findsOneWidget);
    expect(
      tester.widget<AbsorbPointer>(find.byType(AbsorbPointer).first).absorbing,
      isTrue,
    );
  });
}
