/// Constant-time equality for secret-derived hash strings.
///
/// lengths still leak; comparison itself never short-circuits.
bool constantTimeEquals(String a, String b) {
  final aLen = a.length;
  final bLen = b.length;
  var diff = aLen ^ bLen;
  final min = aLen < bLen ? aLen : bLen;
  for (var i = 0; i < min; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
