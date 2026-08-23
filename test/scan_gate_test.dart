import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/sell/scan_gate.dart';

void main() {
  test('same code inside the cooldown window is swallowed exactly once-per '
      'window (one physical scan adds ONE unit even while the barcode '
      'flickers in front of the camera)', () {
    final gate = ScanGate();
    var t = DateTime(2026, 8, 22, 10);
    expect(gate.accept('ABC', t), isTrue);
    // Decoder re-fires milliseconds later — swallowed.
    expect(gate.accept('ABC', t.add(const Duration(milliseconds: 30))), isFalse);
    expect(gate.accept('ABC', t.add(const Duration(milliseconds: 500))), isFalse);

    // After the window expires the same item scans again on purpose.
    expect(gate.accept('ABC', t.add(const Duration(seconds: 2))), isTrue);
  });

  test('different codes never block each other', () {
    final gate = ScanGate();
    final t = DateTime(2026, 8, 22, 10);
    expect(gate.accept('A', t), isTrue);
    expect(gate.accept('B', t.add(const Duration(milliseconds: 5))), isTrue);
    expect(gate.accept('C', t.add(const Duration(milliseconds: 10))), isTrue);
    expect(gate.accept('A', t.add(const Duration(milliseconds: 15))), isFalse,
        reason: 'A itself is still cooling down');
  });

  test('window expiry re-opens the code', () {
    final gate = ScanGate(window: const Duration(seconds: 1));
    final t0 = DateTime(2026, 8, 22, 10);
    expect(gate.accept('X', t0), isTrue);
    expect(gate.accept('X', t0.add(const Duration(milliseconds: 999))), isFalse);
    expect(gate.accept('X', t0.add(const Duration(seconds: 1))), isTrue);
  });
}
