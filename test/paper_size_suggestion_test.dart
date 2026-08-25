import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/invoices/receipt_data.dart';

void main() {
  group('suggestPaperSizeFromDeviceName', () {
    test('suggests 80mm when the name contains "80"', () {
      expect(suggestPaperSizeFromDeviceName('XP-80C'), PaperSize.mm80);
      expect(suggestPaperSizeFromDeviceName('Printer 80mm'), PaperSize.mm80);
    });

    test('suggests 58mm when the name contains "58", "57", or "56"', () {
      expect(suggestPaperSizeFromDeviceName('MTP-58'), PaperSize.mm58);
      expect(suggestPaperSizeFromDeviceName('BT-57 Printer'), PaperSize.mm58);
      expect(suggestPaperSizeFromDeviceName('GP-56'), PaperSize.mm58);
    });

    test('is case-insensitive', () {
      expect(suggestPaperSizeFromDeviceName('THERMAL80'), PaperSize.mm80);
    });

    test('Epson TM-T88-class names land on the narrow (180dpi) width', () {
      expect(suggestPaperSizeFromDeviceName('TM-T88VI'), PaperSize.mm80Narrow);
      expect(suggestPaperSizeFromDeviceName('EPSON TM-T88IV'), PaperSize.mm80Narrow);
    });

    test('returns null for a generic name with no width signal — no false '
        'confidence', () {
      expect(suggestPaperSizeFromDeviceName('BlueTooth Printer'), isNull);
      expect(suggestPaperSizeFromDeviceName(''), isNull);
    });

    test('80 takes precedence over an incidental 58-looking substring '
        'shouldn\'t normally co-occur, but 80 is checked first', () {
      // Documents the actual precedence rule rather than asserting an
      // unrealistic input combination has one "correct" answer.
      expect(suggestPaperSizeFromDeviceName('MTP-80-58'), PaperSize.mm80);
    });
  });
}
