import 'package:dio/dio.dart';
import 'package:mudbase_showcase_docs_search/core/mudbase_exception.dart';
import 'package:test/test.dart';

void main() {
  group('MudbaseException.fromDioException', () {
    test('reads the server "error" message and status code', () {
      final requestOptions = RequestOptions(path: '/api/data/x');
      final dioError = DioException(
        requestOptions: requestOptions,
        response: Response<dynamic>(
          requestOptions: requestOptions,
          statusCode: 403,
          data: {'error': 'Insufficient permissions'},
        ),
        type: DioExceptionType.badResponse,
      );

      final exception = MudbaseException.fromDioException(dioError);

      expect(exception.statusCode, 403);
      expect(exception.message, 'Insufficient permissions');
    });

    test('falls back to "message" field when "error" is absent', () {
      final requestOptions = RequestOptions(path: '/api/data/x');
      final dioError = DioException(
        requestOptions: requestOptions,
        response: Response<dynamic>(
          requestOptions: requestOptions,
          statusCode: 400,
          data: {'message': 'Validation failed'},
        ),
        type: DioExceptionType.badResponse,
      );

      expect(
        MudbaseException.fromDioException(dioError).message,
        'Validation failed',
      );
    });

    test('reads an optional "code" field', () {
      final requestOptions = RequestOptions(path: '/api/auth/local/login');
      final dioError = DioException(
        requestOptions: requestOptions,
        response: Response<dynamic>(
          requestOptions: requestOptions,
          statusCode: 403,
          data: {
            'error': 'Email not verified',
            'code': 'EMAIL_VERIFICATION_REQUIRED',
          },
        ),
        type: DioExceptionType.badResponse,
      );

      expect(
        MudbaseException.fromDioException(dioError).code,
        'EMAIL_VERIFICATION_REQUIRED',
      );
    });

    test(
      'produces a friendly message for a connection timeout with no response',
      () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/api/data/x'),
          type: DioExceptionType.connectionTimeout,
        );

        final exception = MudbaseException.fromDioException(dioError);

        expect(exception.statusCode, 0);
        expect(exception.message, contains('timed out'));
      },
    );

    test('produces a friendly message for a connection error', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/api/data/x'),
        type: DioExceptionType.connectionError,
      );

      expect(
        MudbaseException.fromDioException(dioError).message,
        contains("Couldn't reach"),
      );
    });

    test('toString returns the message', () {
      const exception = MudbaseException('Something failed', 500);
      expect(exception.toString(), 'Something failed');
    });
  });
}
