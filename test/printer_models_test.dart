import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/invoices/receipt_data.dart';
import 'package:mm_pos/features/printing/printer_models.dart';

void main() {
  group('printer model presets', () {
    test('ids are unique and non-empty — they are storage keys', () {
      final ids = kPrinterModels.map((p) => p.id).toSet();
      expect(ids.length, kPrinterModels.length);
      for (final preset in kPrinterModels) {
        expect(preset.id, isNotEmpty);
        expect(preset.label, isNotEmpty);
      }
    });

    test('every preset recommends a real paper size with matching width '
        'family (58 presets → mm58, everything else an 80mm variant)', () {
      for (final preset in kPrinterModels) {
        if (preset.recommendedPaper == PaperSize.mm58) continue;
        expect(
          preset.recommendedPaper,
          anyOf(PaperSize.mm80, PaperSize.mm80Narrow),
          reason: '${preset.id} recommends a non-58 paper',
        );
      }
    });

    test('the narrow (180dpi) recommendation exists for TM-T88 only', () {
      final narrow = kPrinterModels
          .where((p) => p.recommendedPaper == PaperSize.mm80Narrow)
          .toList();
      expect(narrow.map((p) => p.id), ['epson_tmt88']);
    });
  });

  group('printerModelById', () {
    test('finds presets by id, null otherwise', () {
      expect(printerModelById('epson_tmt88')!.brand, 'Epson');
      expect(printerModelById('__custom__'), isNull);
      expect(printerModelById(null), isNull);
      expect(printerModelById(''), isNull);
    });
  });

  group('suggestPrinterModelFromName', () {
    test('matches common Bluetooth device names regardless of separators '
        'or case', () {
      expect(suggestPrinterModelFromName('XP-80C')!.id, 'xprinter_xp80c');
      expect(suggestPrinterModelFromName('XP-365B')!.id, 'xprinter_xp58');
      expect(suggestPrinterModelFromName('EPSON TM-T88VI')!.id, 'epson_tmt88');
      expect(suggestPrinterModelFromName('TM-T82III')!.id, 'epson_tmt82');
      expect(suggestPrinterModelFromName('Rongta RP326')!.id, 'rongta_rp326');
      expect(suggestPrinterModelFromName('ZJ-5890D')!.id, 'zjiang_zj58');
    });

    test('returns null for generic or unknown names — no false confidence', () {
      expect(suggestPrinterModelFromName('Bluetooth Printer'), isNull);
      expect(suggestPrinterModelFromName('POS-9000'), isNull);
      expect(suggestPrinterModelFromName(''), isNull);
    });
  });
}
