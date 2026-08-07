import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/logic/notes_error_message.dart';

void main() {
  test('explains server failures without blaming connectivity', () {
    final error = DioException(
      requestOptions: RequestOptions(path: '/notes'),
      response: Response<void>(
        requestOptions: RequestOptions(path: '/notes'),
        statusCode: 500,
      ),
      type: DioExceptionType.badResponse,
    );

    expect(
      notesErrorMessage(error),
      'NockNock tuvo un problema al guardar. Inténtalo nuevamente en unos minutos.',
    );
  });

  test('explains connection failures as an internet problem', () {
    final error = DioException(
      requestOptions: RequestOptions(path: '/notes'),
      type: DioExceptionType.connectionError,
    );

    expect(
      notesErrorMessage(error),
      'No pudimos conectarnos. Revisa tu conexión a internet e inténtalo nuevamente.',
    );
  });

  test('preserves useful API validation messages including lists', () {
    final error = DioException(
      requestOptions: RequestOptions(path: '/notes'),
      response: Response<Map<String, Object>>(
        requestOptions: RequestOptions(path: '/notes'),
        statusCode: 400,
        data: {
          'message': ['El título es obligatorio', 'El título es muy largo'],
        },
      ),
      type: DioExceptionType.badResponse,
    );

    expect(
      notesErrorMessage(error),
      'El título es obligatorio\nEl título es muy largo',
    );
  });
}
