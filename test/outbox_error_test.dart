import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/sync/outbox_error.dart';

void main() {
  test('classifyOutboxError maps RLS / unique / FK / unknown', () {
    expect(
      classifyOutboxError(
        'PostgresException(message: new row violates row-level security '
        'policy, code: 42501)',
      ),
      OutboxErrorClass.rls42501,
    );
    expect(
      classifyOutboxError('duplicate key value violates unique constraint'),
      OutboxErrorClass.uniqueViolation,
    );
    expect(
      classifyOutboxError('insert or update on table violates foreign key'),
      OutboxErrorClass.foreignKey,
    );
    expect(classifyOutboxError('timeout'), OutboxErrorClass.unknown);
    expect(classifyOutboxError(null), OutboxErrorClass.unknown);
  });

  test('isRlsOutboxError is true only for RLS/42501', () {
    expect(isRlsOutboxError('42501 row-level security'), isTrue);
    expect(isRlsOutboxError('duplicate key'), isFalse);
  });
}
