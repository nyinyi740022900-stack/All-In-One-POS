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
