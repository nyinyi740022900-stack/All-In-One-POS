import 'package:flutter_test/flutter_test.dart';

import 'package:mm_pos/invoices_web/invoices_web_session.dart';

void main() {
  test('sign-in with blank email or password is rejected locally', () async {
    expect(await InvoicesWebSession.signIn('', 'x'), 'empty_signin');
    expect(await InvoicesWebSession.signIn('a@b.c', ''), 'empty_signin');
    expect(await InvoicesWebSession.signIn('  ', 'x'), 'empty_signin');
  });

  test('legacy browser key activation is retired', () async {
    expect(await InvoicesWebSession.activate(''), 'retired_path');
    expect(await InvoicesWebSession.activate('SOME-KEY'), 'retired_path');
  });
}
