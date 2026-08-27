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

  test(
    'isInvoiceNoCollisionError narrows uniqueViolation to the invoice_no '
    'constraint specifically (migration 0074)',
    () {
      expect(
        isInvoiceNoCollisionError(
          'duplicate key value violates unique constraint '
          '"sales_shop_invoice_no_key"',
        ),
        isTrue,
      );
      // Same error class, but a different table's unique index — must not
      // be mislabelled as an invoice collision to the owner.
      expect(
        isInvoiceNoCollisionError(
          'duplicate key value violates unique constraint '
          '"products_shop_sku_key"',
        ),
        isFalse,
      );
      expect(isInvoiceNoCollisionError('foreign key violation'), isFalse);
      expect(isInvoiceNoCollisionError(null), isFalse);
    },
  );
}
