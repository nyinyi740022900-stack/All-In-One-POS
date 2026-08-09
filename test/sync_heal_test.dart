import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/sync/sync_heal.dart';

void main() {
  test('isLedgerSyncTable covers sales and payments', () {
    expect(isLedgerSyncTable('sales'), isTrue);
    expect(isLedgerSyncTable('payments'), isTrue);
    expect(isLedgerSyncTable('categories'), isFalse);
    expect(isLedgerSyncTable('payment_accounts'), isFalse);
  });

  test('isNotFoundOutboxError detects PostgREST empty results', () {
    expect(isNotFoundOutboxError('PostgrestException: PGRST116'), isTrue);
    expect(isNotFoundOutboxError('Results contain 0 rows'), isTrue);
    expect(isNotFoundOutboxError('boom'), isFalse);
  });

  test('isForeignKeyOutboxError', () {
    expect(
      isForeignKeyOutboxError('violates foreign key constraint'),
      isTrue,
    );
    expect(isForeignKeyOutboxError('42501'), isFalse);
  });
}
