import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/invoices/invoice_view.dart';

void main() {
  final now = DateTime(2026, 8, 17, 2, 19);

  InvoiceData invoice({
    String customerName = '',
    String? customerPhone,
    String? deliveryAddress,
    List<InvoiceItemData>? items,
    int discount = 0,
    int deliveryFee = 0,
    int paid = 0,
  }) =>
      InvoiceData(
        currencySymbol: 'Ks',
        exponent: 0,
        shopName: 'Caesar Shop',
        invoiceNo: 'INV-20260817-001',
        date: now,
        customerName: customerName,
        customerPhone: customerPhone,
        deliveryAddress: deliveryAddress,
        items: items ??
            [
              const InvoiceItemData(
                name: 'ကိုကာကိုလာ (ဗူး)',
                qty: 2,
                unitPrice: 700,
                lineTotal: 1400,
              ),
            ],
        discount: discount,
        deliveryFee: deliveryFee,
        paid: paid,
      );

  test('walk-in sale has no customer block', () {
    expect(invoice().hasCustomerDetails, isFalse);
  });

  test('a named customer, phone, or address shows labeled fields', () {
    expect(invoice(customerName: 'Aung').hasCustomerDetails, isTrue);
    expect(invoice(customerPhone: '09').hasCustomerDetails, isTrue);
    expect(invoice(deliveryAddress: 'Yangon').hasCustomerDetails, isTrue);
  });

  test('address joins street and township', () {
    final data = InvoiceData(
      currencySymbol: 'Ks',
      exponent: 0,
      shopName: 'Caesar Shop',
      invoiceNo: 'INV-1',
      date: now,
      customerName: 'Aung',
      deliveryAddress: 'No. 12',
      township: 'Kamayut',
      items: const [
        InvoiceItemData(name: 'Tea', qty: 1, unitPrice: 500, lineTotal: 500),
      ],
    );
    expect(data.formattedAddress, 'No. 12, Kamayut');
  });

  test('total is items minus discount plus delivery', () {
    final data = invoice(discount: 100, deliveryFee: 500);
    expect(data.itemsTotal, 1400);
    expect(data.total, 1800);
  });

  test('amount due is leftover after paid, never negative', () {
    expect(invoice(paid: 400).amountDue, 1000);
    expect(invoice(paid: 1400).amountDue, 0);
    expect(invoice(paid: 2000).amountDue, 0);
  });
}
