import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/sell/hardware_scan_buffer.dart';

void main() {
  late HardwareScanBuffer buf;
  late DateTime t;

  setUp(() {
    buf = HardwareScanBuffer();
    t = DateTime(2026, 8, 21, 12);
  });

  DateTime tick([int ms = 10]) {
    t = t.add(Duration(milliseconds: ms));
    return t;
  }

  test('rapid keys plus Enter yield the barcode', () {
    for (final ch in '12345678'.split('')) {
      expect(buf.add(now: tick(), isTerminator: false, character: ch), isNull);
    }
    expect(
      buf.add(now: tick(), isTerminator: true),
      '12345678',
    );
  });

  test('slow typing plus Enter is ignored', () {
    for (final ch in '1234'.split('')) {
      buf.add(now: tick(200), isTerminator: false, character: ch);
    }
    expect(buf.add(now: tick(), isTerminator: true), isNull);
  });

  test('CR character terminates like Enter', () {
    buf.add(now: tick(), isTerminator: false, character: 'A');
    buf.add(now: tick(), isTerminator: false, character: 'B');
    buf.add(now: tick(), isTerminator: false, character: 'C');
    expect(buf.add(now: tick(), isTerminator: false, character: '\r'), 'ABC');
  });

  test('too-short burst is ignored', () {
    buf.add(now: tick(), isTerminator: false, character: '1');
    buf.add(now: tick(), isTerminator: false, character: '2');
    expect(buf.add(now: tick(), isTerminator: true), isNull);
  });
}
