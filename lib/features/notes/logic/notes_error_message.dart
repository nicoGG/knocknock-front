import 'package:dio/dio.dart';

String notesErrorMessage(Object error) {
  if (error is! DioException) {
    return 'Ocurrió un problema inesperado. Inténtalo nuevamente.';
  }

  final status = error.response?.statusCode;
  final serverMessage = _serverMessage(error.response?.data);

  if (status == 400 &&
      (serverMessage?.contains('property listType should not exist') == true ||
          serverMessage?.contains('property currency should not exist') ==
              true)) {
    return 'Las listas financieras todavía no están disponibles en el servicio. Por ahora puedes crear una lista Normal.';
  }

  if (status != null) {
    return switch (status) {
      400 || 422 => serverMessage ?? 'Revisa los datos e inténtalo nuevamente.',
      402 => serverMessage ?? 'Alcanzaste un límite del propietario de la lista. Revisa NockNock Plus en Configuración.',
      401 => 'Tu sesión venció. Inicia sesión nuevamente.',
      403 => serverMessage ?? 'No tienes permiso para modificar esta lista.',
      404 => serverMessage ?? 'Este contenido ya no está disponible.',
      409 =>
        serverMessage ?? 'El cambio entra en conflicto con datos actuales.',
      429 =>
        'Hiciste demasiados intentos. Espera un momento y vuelve a probar.',
      >= 500 => 'NockNock tuvo un problema al guardar. Inténtalo nuevamente en unos minutos.',
      _ =>
        serverMessage ??
            'No pudimos completar la operación. Inténtalo nuevamente.',
    };
  }

  return switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.transformTimeout =>
      'La conexión tardó demasiado. Revisa tu señal e inténtalo nuevamente.',
    DioExceptionType.connectionError => 'No pudimos conectarnos. Revisa tu conexión a internet e inténtalo nuevamente.',
    DioExceptionType.badCertificate =>
      'No pudimos establecer una conexión segura con NockNock.',
    DioExceptionType.cancel => 'La operación fue cancelada.',
    DioExceptionType.badResponse || DioExceptionType.unknown =>
      'No pudimos completar la operación. Inténtalo nuevamente.',
  };
}

String? _serverMessage(Object? data) {
  if (data is! Map) return null;
  final message = data['message'];
  if (message is String && message.trim().isNotEmpty) return message.trim();
  if (message is List) {
    final messages = message
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (messages.isNotEmpty) return messages.join('\n');
  }
  return null;
}
