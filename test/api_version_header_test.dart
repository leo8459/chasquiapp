import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:scan_agbc/nucleo/configuracion/api_config.dart';
import 'package:scan_agbc/nucleo/red/api_client.dart';

class _LocalHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'el login envía la versión instalada y propaga un rechazo 426 al bloqueo',
    () async {
      PackageInfo.setMockInitialValues(
        appName: 'ChasquiApp',
        packageName: 'com.agbc.scanagbc',
        version: '1.0.5',
        buildNumber: '6',
        buildSignature: '',
      );
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final http = HttpClient();
        final client = ApiClient(
          config: ApiConfig(baseUrl: 'http://127.0.0.1:${server.port}/api/'),
          httpClient: http,
        );
        String? receivedVersion;
        String? receivedPath;
        server.listen((request) async {
          receivedVersion = request.headers.value('X-App-Version');
          receivedPath = request.uri.path;
          await request.drain<void>();
          request.response.statusCode = 426;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'error_code': 'APP_UPDATE_REQUIRED',
              'message': 'Actualiza ChasquiApp para continuar.',
              'required_version': '1.0.6+7',
              'download_url': 'https://example.test/descargas/',
            }),
          );
          await request.response.close();
        });
        try {
          await expectLater(
            client.postJsonMap('/mobile/auth/login', body: {'alias': 'test'}),
            throwsA(
              isA<ApiException>().having((e) => e.statusCode, 'status', 426),
            ),
          );
          expect(receivedVersion, '1.0.5+6');
          expect(receivedPath, '/api/mobile/auth/login');
          expect(client.requiredUpdate.value?['required_version'], '1.0.6+7');
        } finally {
          http.close(force: true);
          client.requiredUpdate.dispose();
          await server.close(force: true);
        }
      }, _LocalHttpOverrides());
    },
  );
}
