/// POS-style scan gating (owner feedback: one physical scan must add EXACTLY
/// one unit, but camera decoders keep re-firing while a barcode sits in
/// frame — mobile_scanner's noDuplicates only suppresses identical
/// CONSECUTIVE captures, so flicker still produced bursts of additions).
///
/// [accept] allows a code through once per [window]; the same code inside
/// the window is swallowed, different codes always pass, and after the
/// window expires the same code passes again (deliberate re-scans of the
/// same item keep working).
class ScanGate {
  ScanGate({this.window = const Duration(milliseconds: 1500)});

  /// How long a just-scanned code stays suppressed. Long enough to cover a
  /// barcode lingering in front of the camera; short enough that scanning
  /// the same item twice on purpose works by pausing a moment.
  final Duration window;

  final _lastAccepted = <String, DateTime>{};

  bool accept(String code, DateTime now) {
    final last = _lastAccepted[code];
    if (last != null && now.difference(last) < window) {
      return false;
    }
    // Opportunistic cleanup so long sessions don't grow the map forever.
    if (_lastAccepted.length > 64) {
      _lastAccepted.removeWhere((_, t) => now.difference(t) > window);
    }
    _lastAccepted[code] = now;
    return true;
  }

  void reset() => _lastAccepted.clear();
}
