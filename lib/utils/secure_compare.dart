/// Constant-time equality for secret-derived hash strings.
///
/// ponytail: lengths are still observable (unavoidable for variable-length
/// strings), but per-character comparison never short-circuits on mismatch.
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
