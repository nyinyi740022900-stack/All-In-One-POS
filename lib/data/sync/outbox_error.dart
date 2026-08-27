/// Classification of [Outbox.lastError] strings for heal / UX decisions.
enum OutboxErrorClass {
  rls42501,
  uniqueViolation,
  foreignKey,
  unknown,
}

OutboxErrorClass classifyOutboxError(String? lastError) {
  if (lastError == null || lastError.isEmpty) return OutboxErrorClass.unknown;
  final lower = lastError.toLowerCase();
  if (lower.contains('row-level security') || lower.contains('42501')) {
    return OutboxErrorClass.rls42501;
  }
  if (lower.contains('duplicate key') ||
      lower.contains('unique constraint') ||
      lower.contains('23505')) {
    return OutboxErrorClass.uniqueViolation;
  }
  if (lower.contains('foreign key') ||
      lower.contains('23503') ||
      lower.contains('violates foreign key')) {
    return OutboxErrorClass.foreignKey;
  }
  return OutboxErrorClass.unknown;
}

bool isRlsOutboxError(String? lastError) =>
    classifyOutboxError(lastError) == OutboxErrorClass.rls42501;

/// True when [lastError] is specifically a collision on
/// `sales_shop_invoice_no_key` (migration 0074) — two offline devices minted
/// the same `INV-yyyyMMdd-NNN` for two different sales. Narrower than
/// [OutboxErrorClass.uniqueViolation] (which also fires for any other
/// table's unique index) so `sync_issues_screen.dart` can show an owner a
/// specific, actionable reason instead of a generic "held" pill.
bool isInvoiceNoCollisionError(String? lastError) {
  if (classifyOutboxError(lastError) != OutboxErrorClass.uniqueViolation) {
    return false;
  }
  final lower = lastError!.toLowerCase();
  return lower.contains('sales_shop_invoice_no_key') ||
      lower.contains('invoice_no');
}
