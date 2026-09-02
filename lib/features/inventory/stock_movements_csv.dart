import 'package:intl/intl.dart';

import '../../core/csv_util.dart';
import '../../core/money.dart';
import 'inventory_providers.dart';

/// Pure: renders the filtered stock-movement ledger as CSV, for handing the
/// shop's stock transactions to an accountant or reconciling a stock take —
/// the same off-ramp [buildInventoryCsv] gives the product list. The caller
/// passes the rows it is already showing ([MovementWithProduct], i.e. the
/// current date/type/product filters applied) so the file can never disagree
/// with the screen; [typeLabel] localizes each movement type the same way
/// the list does.
String buildStockMovementsCsv(
  List<MovementWithProduct> movements, {
  required String dateHeader,
  required String productHeader,
  required String typeHeader,
  required String qtyChangeHeader,
  required String unitCostHeader,
  required String noteHeader,
  required String Function(String type) typeLabel,
  DateFormat? dateFormat,
  int exponent = 0,
}) {
  final fmt = dateFormat ?? DateFormat('yyyy-MM-dd HH:mm');
  return csvDocument(
    [
      dateHeader,
      productHeader,
      typeHeader,
      qtyChangeHeader,
      unitCostHeader,
      noteHeader,
    ],
    [
      for (final mp in movements)
        [
          fmt.format(mp.movement.createdAt),
          mp.productName,
          typeLabel(mp.movement.type),
          mp.movement.qtyDelta,
          formatMinorUnitsPlain(mp.movement.unitCost, exponent: exponent),
          mp.movement.note ?? '',
        ],
    ],
  );
}
