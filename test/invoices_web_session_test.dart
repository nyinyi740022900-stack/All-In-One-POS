import 'package:flutter_test/flutter_test.dart';

import 'package:mm_pos/invoices_web/invoices_web_session.dart';

void main() {
  test('sign-in with blank email or password is rejected locally', () async {
    expect(await InvoicesWebSession.signIn('', 'x'), 'empty_signin');
    expect(await InvoicesWebSession.signIn('a@b.c', ''), 'empty_signin');
    expect(await InvoicesWebSession.signIn('  ', 'x'), 'empty_signin');
  });

  test('activate with a blank key is rejected locally', () async {
    expect(await InvoicesWebSession.activate(''), 'empty_key');
    expect(await InvoicesWebSession.activate('   '), 'empty_key');
  });
}
