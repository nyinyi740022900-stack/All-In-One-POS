import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/invoices/cashier_label.dart';

void main() {
  const members = [
    (id: 's1', name: 'nyi'),
    (id: 's2', name: 'simon'),
  ];

  test('named staff id prints that person', () {
    expect(
      cashierNameForSale(
        staffId: 's1',
        members: members,
        ownerLabel: 'Owner',
      ),
      'nyi',
    );
  });

  test('owner sale (no staff id) prints Owner', () {
    expect(
      cashierNameForSale(
        staffId: null,
        members: members,
        ownerLabel: 'Owner',
        deviceLabel: 'Front desk PC',
      ),
      'Owner',
    );
  });

  test('deleted staff falls back to device label then Owner', () {
    expect(
      cashierNameForSale(
        staffId: 'gone',
        members: members,
        ownerLabel: 'Owner',
        deviceLabel: 'Front desk PC',
      ),
      'Front desk PC',
    );
    expect(
      cashierNameForSale(
        staffId: 'gone',
        members: members,
        ownerLabel: 'Owner',
      ),
      'Owner',
    );
  });

  test('a stamped staff id that does not resolve is Staff, never Owner', () {
    for (final id in ['gone', 'account:user-1']) {
      expect(
        cashierNameForSale(
          staffId: id,
          members: members,
          ownerLabel: 'Owner',
          staffLabel: 'Staff',
        ),
        'Staff',
      );
    }
    expect(
      cashierNameForSale(
        staffId: null,
        members: members,
        ownerLabel: 'Owner',
        staffLabel: 'Staff',
      ),
      'Owner',
    );
  });
}
