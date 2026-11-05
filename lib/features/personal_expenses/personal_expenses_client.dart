import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:nocknock/core/config/app_config.dart';

class PersonalExpensesFailure implements Exception {
  const PersonalExpensesFailure(this.message);
  final String message;
}

class PersonalExpensesClient {
  PersonalExpensesClient({required this.tokenProvider, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: AppConfig.apiBaseUrl,
              connectTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 60),
              receiveTimeout: const Duration(seconds: 60),
            ),
          );
  final Future<String?> Function() tokenProvider;
  final Dio _dio;
  void close() => _dio.close(force: true);

  Future<dynamic> _request(String path, String method, [Object? data]) async {
    final token = await tokenProvider();
    if (token == null || token.isEmpty) {
      throw const PersonalExpensesFailure(
        'Inicia sesión para usar Gastos personales.',
      );
    }
    try {
      final response = await _dio.request<dynamic>(
        '/personal-expenses/$path',
        data: data,
        options: Options(
          method: method,
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      return response.data;
    } on DioException catch (error) {
      final body = error.response?.data;
      final message = body is Map ? body['message'] : null;
      throw PersonalExpensesFailure(
        message is String
            ? message
            : 'No se pudo conectar. Revisa tu conexión e inténtalo nuevamente.',
      );
    }
  }

  Future<List<Map<String, dynamic>>> list() async =>
      (await _request('statements', 'GET') as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  Future<Map<String, dynamic>> preview(Uint8List bytes) async =>
      Map<String, dynamic>.from(
        await _request('preview', 'POST', {'dataBase64': base64Encode(bytes)})
            as Map,
      );
  Future<void> save(Uint8List bytes) async {
    await _request('statements', 'POST', {'dataBase64': base64Encode(bytes)});
  }

  Future<void> remove(String id) async {
    await _request('statements/$id', 'DELETE');
  }
}
