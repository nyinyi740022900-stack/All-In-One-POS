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
}
