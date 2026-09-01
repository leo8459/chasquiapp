import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:scan_agbc/nucleo/configuracion/api_config.dart';
import 'package:flutter/foundation.dart';

const int _jsonIsolateDecodeThreshold = 48 * 1024;

dynamic _decodeJsonPayload(String rawBody) {
  final trimmed = rawBody.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  try {
    return jsonDecode(trimmed);
  } on FormatException {
    final extractedPayload = _extractJsonPayloadFromRaw(trimmed);
    if (extractedPayload == null) {
      rethrow;
    }

    return jsonDecode(extractedPayload);
  }
}

String? _extractJsonPayloadFromRaw(String rawBody) {
  final objectStart = rawBody.indexOf('{');
  final arrayStart = rawBody.indexOf('[');

  var start = -1;
  if (objectStart >= 0 && arrayStart >= 0) {
    start = objectStart < arrayStart ? objectStart : arrayStart;
  } else if (objectStart >= 0) {
    start = objectStart;
  } else if (arrayStart >= 0) {
    start = arrayStart;
  }

  if (start < 0 || start >= rawBody.length) {
    return null;
  }

  final opening = rawBody[start];
  final closing = opening == '{' ? '}' : ']';
  final end = rawBody.lastIndexOf(closing);
  if (end <= start) {
    return null;
  }

  return rawBody.substring(start, end + 1);
}

class ApiClient {
  ApiClient({required ApiConfig config, HttpClient? httpClient})
    : _config = config,
      _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = const Duration(seconds: 12);
    _httpClient.idleTimeout = const Duration(seconds: 5);
    _httpClient.maxConnectionsPerHost = 6;
    _httpClient.autoUncompress = true;
    _httpClient.userAgent = 'ScanAGBC/1.0';
  }

  final ApiConfig _config;
  final HttpClient _httpClient;

  String? _accessToken;

  String? get currentAccessToken => _accessToken;

  void setAccessToken(String? token) {
    final normalized = token?.trim() ?? '';
    _accessToken = normalized.isEmpty ? null : normalized;
  }

  Future<Map<String, dynamic>> getJsonMap(
    String path, {
    Map<String, String?>? queryParameters,
    bool authorize = false,
  }) async {
    final payload = await _send(
      method: 'GET',
      path: path,
      queryParameters: queryParameters,
      authorize: authorize,
      retryCount: 1,
    );
    return _expectMap(payload);
  }

  Future<Map<String, dynamic>> postJsonMap(
    String path, {
    Map<String, dynamic>? body,
    bool authorize = false,
  }) async {
    final payload = await _send(
      method: 'POST',
      path: path,
      jsonBody: body,
      authorize: authorize,
    );
    return _expectMap(payload);
  }

  Future<Map<String, dynamic>> postMultipartMap(
    String path, {
    required Map<String, String> fields,
    required String fileField,
    required List<int> fileBytes,
    required String fileName,
    String contentType = 'image/jpeg',
    List<ApiMultipartFile> extraFiles = const <ApiMultipartFile>[],
    bool authorize = false,
  }) async {
    final payload = await _send(
      method: 'POST',
      path: path,
      authorize: authorize,
      multipart: _MultipartPayload(
        fields: fields,
        files: <ApiMultipartFile>[
          ApiMultipartFile(
            fieldName: fileField,
            fileBytes: fileBytes,
            fileName: fileName,
            contentType: contentType,
          ),
          ...extraFiles,
        ],
      ),
    );
    return _expectMap(payload);
  }

  Future<dynamic> _send({
    required String method,
    required String path,
    Map<String, String?>? queryParameters,
    Map<String, dynamic>? jsonBody,
    _MultipartPayload? multipart,
    bool authorize = false,
    int retryCount = 0,
  }) async {
    var attempt = 0;

    while (true) {
      try {
        final uri = _buildUri(path, queryParameters);
        final request = await _httpClient.openUrl(method, uri);
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'gzip');
        request.persistentConnection = true;

        if (authorize) {
          final token = _accessToken;
          if (token == null || token.isEmpty) {
            throw const ApiException(
              message: 'La sesión expiró. Inicia sesión nuevamente.',
              statusCode: 401,
              code: 'SESSION_EXPIRED',
            );
          }
          request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        }

        if (multipart != null) {
          final boundary =
              '----ScanAgbcBoundary${DateTime.now().microsecondsSinceEpoch}';
          final multipartBody = _buildMultipartBody(boundary, multipart);
          request.headers.contentType = ContentType(
            'multipart',
            'form-data',
            parameters: {'boundary': boundary},
          );
          request.contentLength = multipartBody.length;
          request.add(multipartBody);
        } else if (jsonBody != null) {
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(jsonBody));
        }

        final response = await request.close().timeout(
          Duration(seconds: multipart == null ? 20 : 60),
        );
        final responseBody = await response.transform(utf8.decoder).join();
        final decodedBody = await _tryDecodeJson(responseBody);

        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw _buildApiException(
            statusCode: response.statusCode,
            payload: decodedBody,
          );
        }

        return decodedBody ?? <String, dynamic>{};
      } on ApiException {
        rethrow;
      } on SocketException {
        if (attempt < retryCount) {
          attempt += 1;
          await Future<void>.delayed(const Duration(milliseconds: 350));
          continue;
        }
        throw const ApiException(
          message:
              'No pudimos conectarnos en este momento. Revisa tu internet y vuelve a intentarlo.',
          statusCode: 503,
          code: 'NETWORK_UNAVAILABLE',
        );
      } on HandshakeException {
        throw const ApiException(
          message:
              'No pudimos establecer una conexión segura. Intenta nuevamente en unos momentos.',
          statusCode: 503,
          code: 'TLS_HANDSHAKE_ERROR',
        );
      } on TimeoutException {
        if (attempt < retryCount) {
          attempt += 1;
          await Future<void>.delayed(const Duration(milliseconds: 350));
          continue;
        }
        throw const ApiException(
          message:
              'La conexión está tardando más de lo esperado. Intenta nuevamente.',
          statusCode: 504,
          code: 'REQUEST_TIMEOUT',
        );
      } on HttpException catch (error) {
        throw ApiException(
          message: error.message,
          statusCode: 503,
          code: 'HTTP_ERROR',
        );
      } on FormatException {
        throw const ApiException(
          message:
              'Recibimos una respuesta que no pudimos leer. Intenta nuevamente.',
          statusCode: 502,
          code: 'INVALID_RESPONSE',
        );
      }
    }
  }

  Uri _buildUri(String path, Map<String, String?>? queryParameters) {
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    final resolved = _config.baseUri.resolve(normalizedPath);
    if (queryParameters == null || queryParameters.isEmpty) {
      return resolved;
    }

    final sanitizedQuery = <String, String>{};
    for (final entry in queryParameters.entries) {
      final value = entry.value?.trim() ?? '';
      if (value.isEmpty) {
        continue;
      }
      sanitizedQuery[entry.key] = value;
    }

    if (sanitizedQuery.isEmpty) {
      return resolved;
    }

    return resolved.replace(
      queryParameters: <String, String>{
        ...resolved.queryParameters,
        ...sanitizedQuery,
      },
    );
  }

  List<int> _buildMultipartBody(String boundary, _MultipartPayload payload) {
    final builder = BytesBuilder(copy: false);

    for (final entry in payload.fields.entries) {
      builder.add(utf8.encode('--$boundary\r\n'));
      builder.add(
        utf8.encode(
          'Content-Disposition: form-data; name="${entry.key}"\r\n\r\n',
        ),
      );
      builder.add(utf8.encode(entry.value));
      builder.add(utf8.encode('\r\n'));
    }

    for (final file in payload.files) {
      builder.add(utf8.encode('--$boundary\r\n'));
      builder.add(
        utf8.encode(
          'Content-Disposition: form-data; name="${file.fieldName}"; '
          'filename="${file.fileName}"\r\n',
        ),
      );
      builder.add(utf8.encode('Content-Type: ${file.contentType}\r\n\r\n'));
      builder.add(file.fileBytes);
      builder.add(utf8.encode('\r\n'));
    }
    builder.add(utf8.encode('--$boundary--\r\n'));

    return builder.takeBytes();
  }

  Future<dynamic> _tryDecodeJson(String rawBody) async {
    final trimmed = rawBody.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    if (trimmed.length >= _jsonIsolateDecodeThreshold) {
      return compute(_decodeJsonPayload, trimmed);
    }

    return _decodeJsonPayload(trimmed);
  }

  Map<String, dynamic> _expectMap(dynamic payload) {
    if (payload is Map<String, dynamic>) {
      return payload;
    }
    if (payload is Map) {
      return payload.map((key, value) => MapEntry(key.toString(), value));
    }

    throw const ApiException(
      message:
          'Recibimos información inesperada. Intenta nuevamente en un momento.',
      statusCode: 502,
      code: 'UNEXPECTED_PAYLOAD',
    );
  }

  ApiException _buildApiException({required int statusCode, dynamic payload}) {
    Map<String, dynamic>? normalizedPayload;
    if (payload is Map<String, dynamic>) {
      normalizedPayload = payload;
    } else if (payload is Map) {
      normalizedPayload = payload.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }

    final code =
        normalizedPayload?['error_code']?.toString().trim().isNotEmpty == true
        ? normalizedPayload!['error_code'].toString().trim()
        : normalizedPayload?['code']?.toString().trim();
    final message =
        _extractMessage(normalizedPayload) ??
        _fallbackMessageForStatusCode(statusCode);

    return ApiException(message: message, statusCode: statusCode, code: code);
  }

  String? _extractMessage(Map<String, dynamic>? payload) {
    if (payload == null) {
      return null;
    }

    final directMessage = payload['message']?.toString().trim() ?? '';
    if (directMessage.isNotEmpty) {
      return directMessage;
    }

    final errors = payload['errors'];
    if (errors is Map) {
      for (final value in errors.values) {
        if (value is List && value.isNotEmpty) {
          final first = value.first.toString().trim();
          if (first.isNotEmpty) {
            return first;
          }
        }

        final text = value?.toString().trim() ?? '';
        if (text.isNotEmpty) {
          return text;
        }
      }
    }

    return null;
  }

  String _fallbackMessageForStatusCode(int statusCode) {
    switch (statusCode) {
      case 401:
        return 'La sesión expiró. Inicia sesión nuevamente.';
      case 403:
        return 'No tienes permisos para realizar esta acción.';
      case 404:
        return 'No encontramos la información que buscas.';
      case 422:
        return 'Algunos datos no se pudieron validar. Revísalos e intenta otra vez.';
      case 503:
        return 'El servicio no está disponible en este momento. Intenta más tarde.';
      default:
        return 'No pudimos completar la solicitud. Intenta nuevamente.';
    }
  }
}

class ApiException implements Exception {
  const ApiException({required this.message, this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  @override
  String toString() => message;
}

class ApiMultipartFile {
  const ApiMultipartFile({
    required this.fieldName,
    required this.fileBytes,
    required this.fileName,
    required this.contentType,
  });

  final String fieldName;
  final List<int> fileBytes;
  final String fileName;
  final String contentType;
}

class _MultipartPayload {
  const _MultipartPayload({required this.fields, required this.files});

  final Map<String, String> fields;
  final List<ApiMultipartFile> files;
}
