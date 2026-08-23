import 'package:flutter_test/flutter_test.dart';
import 'package:locker/services/remote/server_errors.dart';

void main() {
  test('maps raw exceptions to human messages, never leaks them', () {
    expect(describeServerError(Exception('DioException [connection timeout]')),
        contains("Couldn't reach the server"));
    expect(describeServerError(Exception('Connection refused')),
        contains('refused the connection'));
    expect(describeServerError(Exception('401 Unauthorized')),
        contains('username and password'));
    expect(describeServerError(Exception('CERTIFICATE_VERIFY_FAILED')),
        contains('certificate'));
    expect(describeServerError(Exception('Connection closed before status')),
        contains('dropped'));
    expect(describeServerError(Exception('SocketException: failed host lookup')),
        contains('Network error'));
    expect(
        describeServerError(const FormatException('Manifest blob too short')),
        contains("couldn't be read"));
    expect(describeServerError(StateError('Missing blob for remote entry x')),
        'Missing blob for remote entry x');
    expect(describeServerError(Exception('weird unknown failure')),
        isNot(contains('Exception')));
  });
}
