/// Assembles a barcode from a USB / Bluetooth HID "keyboard wedge" scanner.
///
/// Those devices type the code as rapid keystrokes and finish with Enter
/// (or Tab / CR). Human typing is much slower, so a gap larger than
/// [maxInterKey] starts a new buffer and a terminator with fewer than
/// [minLength] characters is ignored.
class HardwareScanBuffer {
  HardwareScanBuffer({
    this.maxInterKey = const Duration(milliseconds: 80),
    this.minLength = 3,
    this.maxLength = 64,
  });

  final Duration maxInterKey;
  final int minLength;
  final int maxLength;

  String _buf = '';
  DateTime? _last;

  bool get isLikelyScan => _buf.length >= 2;

  void reset() {
    _buf = '';
    _last = null;
  }

  /// Returns a completed code, or null if this event only updated the buffer.
  String? add({
    required DateTime now,
    required bool isTerminator,
    String? character,
  }) {
    if (isTerminator) {
      final code = _buf;
      reset();
      if (code.length >= minLength && code.length <= maxLength) return code;
      return null;
    }
    if (character == null || character.isEmpty) return null;
    if (character == '\n' || character == '\r') {
      return add(now: now, isTerminator: true);
    }
    if (character.length != 1) return null;
    final unit = character.codeUnitAt(0);
    if (unit < 32 || unit == 127) return null;

    if (_last != null && now.difference(_last!) > maxInterKey) {
      _buf = '';
    }
    _last = now;
    _buf += character;
    if (_buf.length > maxLength) reset();
    return null;
  }
}
