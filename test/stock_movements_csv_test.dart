import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/features/inventory/inventory_providers.dart';
import 'package:mm_pos/features/inventory/stock_movements_csv.dart';

StockMovement _movement(
  String id, {
  String type = 'purchase',
  int qtyDelta = 10,
  int unitCost = 0,
  String? note,
}) =>
    StockMovement(
      id: id,
      shopId: 'shop-1',
      createdAt: DateTime(2026, 8, 24, 14, 30),
      updatedAt: DateTime(2026, 8, 24, 14, 30),
      dirty: true,
      isDeleted: false,
      productId: 'p-1',
      type: type,
      qtyDelta: qtyDelta,
      unitCost: unitCost,
      note: note,
    );

MovementWithProduct _row(StockMovement m, String name) =>
    MovementWithProduct(movement: m, productName: name);

void main() {
  test('renders header + one row per movement with localized type', () {
    final csv = buildStockMovementsCsv(
      [
        _row(_movement('m1', type: 'purchase', qtyDelta: 100, unitCost: 5000),
            'Powerbank'),
        _row(_movement('m2', type: 'sale', qtyDelta: -2), 'Powerbank'),
        _row(
          _movement('m3', type: 'adjustment', qtyDelta: 1, note: 'damaged, count'),
          'Sharp ဓာတ်ဆီ',
        ),
      ],
      dateHeader: 'Date',
      productHeader: 'Product',
      typeHeader: 'Type',
      qtyChangeHeader: 'Qty change',
      unitCostHeader: 'Unit cost',
      noteHeader: 'Note',
      typeLabel: (t) => switch (t) {
        'purchase' => 'Restock',
        'sale' => 'Sale',
        _ => 'Adjustment',
      },
      dateFormat: DateFormat('yyyy-MM-dd HH:mm'),
    );

    final lines = csv.split('\r\n');
    expect(lines.first, 'Date,Product,Type,Qty change,Unit cost,Note');
    expect(lines[1], '2026-08-24 14:30,Powerbank,Restock,100,5000,');
    expect(lines[2], '2026-08-24 14:30,Powerbank,Sale,-2,0,');
    // A note containing a comma must be quoted, not split the row; the
    // Myanmar product name has no comma so it stays bare.
    expect(lines[3], '2026-08-24 14:30,Sharp ဓာတ်ဆီ,Adjustment,1,0,"damaged, count"');
    expect(lines, hasLength(4));
  });

  test('empty ledger renders header only', () {
    final csv = buildStockMovementsCsv(
      const [],
      dateHeader: 'Date',
      productHeader: 'Product',
      typeHeader: 'Type',
      qtyChangeHeader: 'Qty change',
      unitCostHeader: 'Unit cost',
      noteHeader: 'Note',
      typeLabel: (t) => t,
    );
    expect(csv, 'Date,Product,Type,Qty change,Unit cost,Note');
  });
}
