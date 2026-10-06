import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/services/remote/remote_store.dart';
import 'package:locker/services/remote/server_errors.dart';

void main() {
  test('errors explain recovery without exposing internal details', () {
    for (final raw in [
      'Connection refused',
      'connection timeout',
      'connection closed'
    ]) {
      expect(describeServerError(Exception(raw)), contains('network'));
    }
    expect(describeServerError(Exception('401 Unauthorized')),
        contains('username and password'));
    expect(describeServerError(Exception('CERTIFICATE_VERIFY_FAILED')),
        contains('secure connection'));
    expect(describeServerError(const FormatException('private filename')),
        contains('couldn’t be verified'));
    expect(
        describeServerError(
            StateError("Instance of 'InvalidCipherTextException'")),
        contains('couldn’t be verified'));
    expect(describeServerError(RemoteRevisionChanged()),
        contains('Another device'));
    expect(describeServerError(UnsafeRemotePublication()),
        contains('Desktop Backup'));
    for (final error in [
      StateError('Missing blob for remote entry private-id'),
      Exception('password=secret')
    ]) {
      final message = describeServerError(error);
      expect(message, isNot(contains('private-id')));
      expect(message, isNot(contains('secret')));
      expect(message, isNot(contains('Exception')));
    }
  });

  test('HTTP status, rather than URL or response body, determines the message',
      () {
    final request = RequestOptions(path: '/private?token=secret');
    final error = DioException(
        requestOptions: request,
        response: Response(requestOptions: request, statusCode: 507));
    expect(describeServerError(error), contains('free space'));
    expect(describeServerError(error), isNot(contains('secret')));
  });
}
