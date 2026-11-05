import 'package:package_info_plus/package_info_plus.dart';

final _appVersionPattern = RegExp(r'^\d+\.\d+\.\d+\+\d+$');

class InstalledAppVersion {
  static Future<String> read() async {
    final info = await PackageInfo.fromPlatform();
    final version = '${info.version}+${info.buildNumber}';
    if (!_appVersionPattern.hasMatch(version)) {
      throw const FormatException('No se pudo leer la versión instalada.');
    }
    return version;
  }
}

class AppVersionRequirement {
  const AppVersionRequirement({
    required this.version,
    required this.downloadUri,
  });

  final String version;
  final Uri downloadUri;

  factory AppVersionRequirement.fromJson(Map<String, dynamic> json) {
    final version = json['required_version']?.toString() ?? '';
    final uri = Uri.tryParse(json['download_url']?.toString() ?? '');
    if (!_appVersionPattern.hasMatch(version) ||
        uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException(
        'La configuración de actualización no es válida.',
      );
    }
    return AppVersionRequirement(version: version, downloadUri: uri);
  }
}
