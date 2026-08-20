import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/account/saved_login_store.dart';

void main() {
  test('savedLoginMatchesEmail is case-insensitive and trims', () {
    expect(savedLoginMatchesEmail('A@Shop.com', 'a@shop.com'), isTrue);
    expect(savedLoginMatchesEmail(' a@shop.com ', 'A@shop.com'), isTrue);
    expect(savedLoginMatchesEmail('other@shop.com', 'a@shop.com'), isFalse);
    expect(savedLoginMatchesEmail('', 'a@shop.com'), isFalse);
  });

  test('SavedLoginBinder fills password only when the typed email matches', () {
    final email = TextEditingController();
    final password = TextEditingController();
    addTearDown(email.dispose);
    addTearDown(password.dispose);
    final binder = SavedLoginBinder(email: email, password: password)..attach();
    addTearDown(binder.detach);

    binder.applySaved(
      const SavedLogin(email: 'owner@shop.com', password: 'secret1'),
    );
    expect(email.text, 'owner@shop.com');
    expect(password.text, 'secret1');

    email.text = 'staff@shop.com';
    expect(password.text, isEmpty);

    email.text = 'OWNER@shop.com';
    expect(password.text, 'secret1');

    password.text = 'typed-by-user';
    email.text = 'staff@shop.com';
    expect(password.text, 'typed-by-user');

    password.clear();
    email.text = 'owner@shop.com';
    binder.refillIfMatch();
    expect(password.text, 'secret1');

    binder.forget();
    expect(password.text, isEmpty);
    email.text = 'owner@shop.com';
    binder.refillIfMatch();
    expect(password.text, isEmpty);
  });
}
