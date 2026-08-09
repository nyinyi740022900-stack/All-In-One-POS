import 'outbox_error.dart';

/// Append-only / money / stock ledger tables — never silently drop on
/// `rejected_invalid`; keep queued for a later app heal + Sentry.
const kLedgerSyncTables = {
  'sales',
  'sale_items',
  'payments',
  'stock_levels',
  'stock_movements',
  'credit_payments',
  'supplier_payments',
  'orders',
  'order_items',
  'expenses',
  'cash_sessions',
  'equity_entries',
  'purchase_orders',
  'purchase_order_items',
  'license_payments',
};

bool isLedgerSyncTable(String table) => kLedgerSyncTables.contains(table);

bool isNotFoundOutboxError(String? lastError) {
  if (lastError == null || lastError.isEmpty) return false;
  final lower = lastError.toLowerCase();
  return lower.contains('pgrst116') ||
      lower.contains('results contain 0 rows') ||
      lower.contains('statuscode: 404') ||
      lower.contains('status: 404') ||
      (lower.contains('not found') && lower.contains('404'));
}

bool isForeignKeyOutboxError(String? lastError) =>
    classifyOutboxError(lastError) == OutboxErrorClass.foreignKey;
