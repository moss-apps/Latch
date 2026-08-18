import 'package:flutter_test/flutter_test.dart';
import 'package:locker/services/pb/pocketbase_runtime.dart';

void main() {
  test('PbHandshakeParser extracts port/token/ready and ignores junk', () {
    final parser = PbHandshakeParser();

    // stdout is contractually handshake-only, but parsing must survive noise.
    for (final line in [
      'some go runtime noise',
      'LOCKER_PB_TOKEN=not-the-real-one-yet', // overwritten by the real one
    ]) {
      parser.feed(line);
    }
    expect(parser.isComplete, isFalse);

    expect(
      parser.feed('LOCKER_PB_PORT=41235'),
      isFalse, // still missing token + ready
    );
    expect(parser.port, 41235);

    expect(
      parser.feed('LOCKER_PB_TOKEN=${'a' * 64}'),
      isFalse, // still missing ready
    );
    expect(parser.token, 'a' * 64);

    expect(parser.feed('LOCKER_PB_READY=1'), isTrue);
    expect(parser.isComplete, isTrue);

    // Post-handshake lines change nothing.
    expect(parser.feed('later log line'), isTrue);
    expect(parser.port, 41235);
  });

  test('PbHandshakeParser stays incomplete when required lines are absent',
      () {
    final parser = PbHandshakeParser()
      ..feed('LOCKER_PB_PORT=1')
      ..feed('LOCKER_PB_TOKEN=${'b' * 64}');
    expect(parser.isComplete, isFalse);
  });

  test('PbHandshakeParser rejects garbage ports', () {
    final parser = PbHandshakeParser()
      ..feed('LOCKER_PB_PORT=not-a-number')
      ..feed('LOCKER_PB_TOKEN=${'c' * 64}')
      ..feed('LOCKER_PB_READY=1');
    expect(parser.isComplete, isFalse); // port never parsed
    expect(parser.port, isNull);
  });
}
