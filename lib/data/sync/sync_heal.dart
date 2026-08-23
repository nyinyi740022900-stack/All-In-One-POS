import 'outbox_error.dart';

/// Directory-like tables whose local rows may SAFELY outlive a permanently
/// rejected push (a product/customer/staff entry can sit local-only for UI
/// purposes without corrupting books). Everything else in the [syncTables]
/// registry — money / stock / append-only ledgers — is treated as protected.
///
/// Deliberately INVERTED from the old hardcoded `kLedgerSyncTables` allow-
/// list (audit Low #1): adding a new synced table without touching this
/// file now defaults it to PROTECTED (never silently dropped on
/// `rejected_invalid`) instead of silently droppable. A typo here shrinks
/// protection by one directory table, never loses a ledger row.
const kNonLedgerSyncTables = {
  'categories',
  'products',
  'customers',
  'suppliers',
  'staff_members',
  'device_labels',
  'recurring_expenses',
  'payment_accounts',
  'shop_profiles',
};

bool isLedgerSyncTable(String table) =>
    !kNonLedgerSyncTables.contains(table);

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
