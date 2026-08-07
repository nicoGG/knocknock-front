import 'dart:async';

import 'package:dio/dio.dart';
import 'package:nocknock/core/telemetry/app_telemetry.dart';
import 'package:uuid/uuid.dart';

const _requestIdExtraKey = 'nocknock_request_id';

Dio createTelemetryDio(BaseOptions options, {AppTelemetry? telemetry}) {
  final dio = Dio(options);
  if (telemetry != null) {
    dio.interceptors.add(_TelemetryInterceptor(telemetry));
  }
  return dio;
}

class _TelemetryInterceptor extends Interceptor {
  _TelemetryInterceptor(this.telemetry);

  final AppTelemetry telemetry;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final requestId = const Uuid().v4();
      options.extra[_requestIdExtraKey] = requestId;
      options.headers['X-Request-Id'] = requestId;
      options.headers.addAll(await telemetry.analyticsRequestHeaders());
      await telemetry.noteApiRequest(
        method: options.method,
        requestId: requestId,
        route: sanitizeTelemetryRoute(options.uri.path),
      );
    } catch (_) {
      // Observability must never prevent the product request.
    }
    handler.next(options);
  }

  @override
  void onError(DioException error, ErrorInterceptorHandler handler) {
    final options = error.requestOptions;
    final responseRequestId = error.response?.headers.value('x-request-id');
    final requestId = responseRequestId?.trim().isNotEmpty == true
        ? responseRequestId!.trim()
        : options.extra[_requestIdExtraKey]?.toString() ?? 'unknown';
    final statusCode = error.response?.statusCode;
    final category = _errorCategory(error);
    final reportToCrashlytics =
        (statusCode != null && statusCode >= 500) ||
        error.type == DioExceptionType.badCertificate ||
        error.type == DioExceptionType.unknown;

    unawaited(
      telemetry.recordApiFailure(
        category: category,
        method: options.method,
        requestId: requestId,
        route: sanitizeTelemetryRoute(options.uri.path),
        reportToCrashlytics: reportToCrashlytics,
        statusCode: statusCode,
      ),
    );
    handler.next(error);
  }
}

String sanitizeTelemetryRoute(String path) {
  final segments = path.split('/');
  const idContainers = {
    'collaborators',
    'devices',
    'lists',
    'notes',
    'notifications',
  };
  const staticSegments = {
    'appearance',
    'collaborators',
    'devices',
    'invitations',
    'pinned',
    'read',
    'read-all',
    'reorder',
  };

  for (var index = 1; index < segments.length; index++) {
    final previous = segments[index - 1];
    final current = segments[index];
    if (idContainers.contains(previous) &&
        current.isNotEmpty &&
        !staticSegments.contains(current)) {
      segments[index] = ':id';
    }
  }
  return segments.join('/');
}

String _errorCategory(DioException error) {
  final statusCode = error.response?.statusCode;
  if (statusCode != null) return 'http_$statusCode';
  return switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.transformTimeout => 'timeout',
    DioExceptionType.connectionError => 'connection',
    DioExceptionType.badCertificate => 'certificate',
    DioExceptionType.cancel => 'cancelled',
    DioExceptionType.badResponse => 'invalid_response',
    DioExceptionType.unknown => 'unknown',
  };
}
