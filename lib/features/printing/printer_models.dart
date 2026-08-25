import '../invoices/receipt_data.dart';

/// A known receipt-printer make/model sold and used in Myanmar shops, with
/// the paper width it ships expecting. Picking one is a convenience that
/// pre-sets the paper size correctly — everything still works without it
/// ("Other / not listed" just means "no preset").
///
/// The list is deliberately curated, not exhaustive: every entry here is a
/// model line commonly imported/retailed in Myanmar (Xprinter/Rongta clones
/// dominate the cheap end, Epson TM the mid range, plus the generic
/// no-brand Bluetooth units). [aliases] feed
/// [suggestPrinterModelFromName] against whatever name Bluetooth pairing
/// reports, which for these devices is usually a close variant of the model
/// number.
class PrinterModelPreset {
  const PrinterModelPreset({
    required this.id,
    required this.brand,
    required this.model,
    required this.recommendedPaper,
    this.aliases = const [],
  });

  /// Stable storage id (`printer.model.<mac>` setting).
  final String id;
  final String brand;
  final String model;

  /// Paper size applied when this preset is picked.
  final PaperSize recommendedPaper;

  /// Lowercase fragments matched (substring) against a device name.
  final List<String> aliases;

  String get label => '$brand $model';
}

const kPrinterModels = <PrinterModelPreset>[
  // ---- Xprinter (the most common budget brand in Myanmar shops) --------
  PrinterModelPreset(
    id: 'xprinter_xp58',
    brand: 'Xprinter',
    model: 'XP-58 / XP-365B',
    recommendedPaper: PaperSize.mm58,
    aliases: ['xp-58', 'xp58', 'xp-365', 'xp365'],
  ),
  PrinterModelPreset(
    id: 'xprinter_xp80c',
    brand: 'Xprinter',
    model: 'XP-80C / XP-Q200',
    recommendedPaper: PaperSize.mm80,
    aliases: ['xp-80', 'xp80', 'xp-q200', 'xpq200', 'xp-n160', 'xpn160'],
  ),
  // ---- Epson ------------------------------------------------------------
  PrinterModelPreset(
    id: 'epson_tmt82',
    brand: 'Epson',
    model: 'TM-T82',
    recommendedPaper: PaperSize.mm80,
    aliases: ['tm-t82', 'tmt82'],
  ),
  PrinterModelPreset(
    id: 'epson_tmt20',
    brand: 'Epson',
    model: 'TM-T20',
    recommendedPaper: PaperSize.mm80,
    aliases: ['tm-t20', 'tmt20', 'tm-t81', 'tm-t83'],
  ),
  PrinterModelPreset(
    id: 'epson_tmt88',
    brand: 'Epson',
    model: 'TM-T88',
    recommendedPaper: PaperSize.mm80Narrow,
    aliases: ['tm-t88', 'tmt88'],
  ),
  PrinterModelPreset(
    id: 'epson_tmm30',
    brand: 'Epson',
    model: 'TM-m30',
    recommendedPaper: PaperSize.mm80,
    aliases: ['tm-m30', 'tmm30'],
  ),
  // ---- Rongta -----------------------------------------------------------
  PrinterModelPreset(
    id: 'rongta_rp58',
    brand: 'Rongta',
    model: 'RP58',
    recommendedPaper: PaperSize.mm58,
    aliases: ['rp58', 'rp-58'],
  ),
  PrinterModelPreset(
    id: 'rongta_rp326',
    brand: 'Rongta',
    model: 'RP326 / RP80',
    recommendedPaper: PaperSize.mm80,
    aliases: ['rp326', 'rp-326', 'rp80', 'rp-80', 'rp332', 'rp80use'],
  ),
  // ---- Other brands seen in the market ----------------------------------
  PrinterModelPreset(
    id: 'gprinter_gp58',
    brand: 'Gprinter',
    model: 'GP-58',
    recommendedPaper: PaperSize.mm58,
    aliases: ['gp-58', 'gp58', 'gp-56'],
  ),
  PrinterModelPreset(
    id: 'gprinter_gp80',
    brand: 'Gprinter',
    model: 'GP-80',
    recommendedPaper: PaperSize.mm80,
    aliases: ['gp-80', 'gp80'],
  ),
  PrinterModelPreset(
    id: 'zjiang_zj58',
    brand: 'Zjiang',
    model: 'ZJ-58',
    recommendedPaper: PaperSize.mm58,
    aliases: ['zj-58', 'zj58', 'zjiang'],
  ),
  PrinterModelPreset(
    id: 'bixolon_srp330',
    brand: 'Bixolon',
    model: 'SRP-330 / SRP-350',
    recommendedPaper: PaperSize.mm80,
    aliases: ['srp-330', 'srp330', 'srp-350', 'srp350'],
  ),
  PrinterModelPreset(
    id: 'citizen_cts651',
    brand: 'Citizen',
    model: 'CT-S651',
    recommendedPaper: PaperSize.mm80,
    aliases: ['ct-s651', 'cts651', 'ct-s310'],
  ),
  PrinterModelPreset(
    id: 'hprt_tp808',
    brand: 'HPRT',
    model: 'TP808',
    recommendedPaper: PaperSize.mm80,
    aliases: ['tp808', 'tp-808', 'hprt'],
  ),
  // ---- No-name hardware -------------------------------------------------
  PrinterModelPreset(
    id: 'generic_58',
    brand: 'Generic',
    model: '58 mm thermal',
    recommendedPaper: PaperSize.mm58,
    aliases: [],
  ),
  PrinterModelPreset(
    id: 'generic_80',
    brand: 'Generic',
    model: '80 mm thermal',
    recommendedPaper: PaperSize.mm80,
    aliases: [],
  ),
];

PrinterModelPreset? printerModelById(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final preset in kPrinterModels) {
    if (preset.id == id) return preset;
  }
  return null;
}

/// Sentinel picker value for "Other / not listed" — a printer whose exact
/// model isn't in [kPrinterModels]. Stored as-is so the choice sticks.
const kPrinterModelCustomId = '__custom__';

/// Best-effort guess of a paired printer's preset from its OS-reported
/// Bluetooth/Wi-Fi name. Returns null when nothing matches confidently —
/// callers fall back to "Other / not listed".
PrinterModelPreset? suggestPrinterModelFromName(String name) {
  final n = name.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
  for (final preset in kPrinterModels) {
    for (final alias in preset.aliases) {
      if (n.contains(alias.replaceAll(RegExp(r'[\s_-]'), ''))) return preset;
    }
  }
  return null;
}
