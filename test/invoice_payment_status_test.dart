import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/invoices/invoice_payment_status.dart';

void main() {
  test('full tender is paid', () {
    expect(invoicePaymentStatusCode(paid: 1000, total: 1000), 'paid');
    expect(invoicePaymentStatusCode(paid: 1200, total: 1000), 'paid');
  });

  test('zero-total invoice is paid', () {
    expect(invoicePaymentStatusCode(paid: 0, total: 0), 'paid');
  });

  test('a down payment is partial', () {
    expect(invoicePaymentStatusCode(paid: 500, total: 1000), 'partial');
  });

  test('nothing tendered is unpaid', () {
    expect(invoicePaymentStatusCode(paid: 0, total: 1000), 'unpaid');
  });

  test('refund of a fully-paid sale is paid (negated ledger row)', () {
    expect(invoicePaymentStatusCode(paid: -1000, total: -1000), 'paid');
  });

  test('refund of a partial credit sale is partial', () {
    expect(invoicePaymentStatusCode(paid: -400, total: -1000), 'partial');
  });

  test('refund of an unpaid credit sale is unpaid, not paid', () {
    expect(invoicePaymentStatusCode(paid: 0, total: -1000), 'unpaid');
  });

  group('credit-book outstanding override (repayments never mutate the sale)',
      () {
    test('fully repaid via credit book reads paid, not unpaid', () {
      expect(
        invoicePaymentStatusCode(paid: 0, total: 10000, outstanding: 0),
        'paid',
      );
    });

    test('partially repaid reads partial with the remaining figure', () {
      expect(
        invoicePaymentStatusCode(paid: 2000, total: 10000, outstanding: 3000),
        'partial',
      );
    });

    test('no override keeps the raw behaviour', () {
      expect(invoicePaymentStatusCode(paid: 0, total: 10000), 'unpaid');
    });
  });

  group('outstandingForDisplay', () {
    test('uses the FIFO map when the sale is known', () {
      expect(
        outstandingForDisplay(
          total: 10000,
          paid: 0,
          isRefundRow: false,
          owedBySaleId: const {'sale-1': 0},
          saleId: 'sale-1',
        ),
        0,
      );
    });

    test('falls back to raw difference without the map', () {
      expect(
        outstandingForDisplay(
          total: 10000,
          paid: 2000,
          isRefundRow: false,
        ),
        8000,
      );
    });

    test('refund rows ignore the allocation and clamp to zero', () {
      expect(
        outstandingForDisplay(
          total: -5000,
          paid: 0,
          isRefundRow: true,
          owedBySaleId: const {'sale-1': 3000},
          saleId: 'sale-1',
        ),
        0,
      );
    });
  });
}
