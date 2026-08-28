/// Digit-append math for the flat-kyat amount pad (order/line discount).
///
/// [d] is a keypad token: a single digit `'0'`–`'9'`, or `'00'`.
int appendPadDigits(int value, String d) {
  final parsed = int.parse(d);
  final factor = d == '00' ? 100 : 10;
  final next = value * factor + parsed;
  if ('$next'.length > 10) return value;
  return next;
}
