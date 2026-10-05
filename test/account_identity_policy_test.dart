import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mm_pos/features/account/account_identity_policy.dart';

UserIdentity identity(String id, String provider, {bool verified = true}) =>
    UserIdentity(
      id: id,
      userId: 'owner',
      identityId: id,
      identityData: {'email': '$id@example.com', 'email_verified': verified},
      provider: provider,
      createdAt: '',
      lastSignInAt: '',
    );
void main() {
  test('the last Google login cannot be removed', () {
    expect(canRemoveGoogleIdentity([identity('old', 'google')], 'old'), false);
  });
  test('new Google login is verified before old Google can be removed', () {
    expect(
      canRemoveGoogleIdentity([
        identity('old', 'google'),
        identity('new', 'google'),
      ], 'old'),
      true,
    );
    expect(
      canRemoveGoogleIdentity([
        identity('old', 'google'),
        identity('new', 'google', verified: false),
      ], 'old'),
      false,
    );
  });
  test('another account or non-Google identity cannot be removed', () {
    expect(
      canRemoveGoogleIdentity([
        identity('old', 'google'),
        identity('mail', 'email'),
      ], 'other'),
      false,
    );
    expect(
      canRemoveGoogleIdentity([
        identity('old', 'google'),
        identity('mail', 'email'),
      ], 'mail'),
      false,
    );
  });
  test('verified email provides a remaining recovery route', () {
    expect(
      canRemoveGoogleIdentity([
        identity('old', 'google'),
        identity('mail', 'email'),
      ], 'old'),
      true,
    );
    expect(
      canRemoveGoogleIdentity([
        identity('old', 'google'),
        identity('mail', 'email', verified: false),
      ], 'old'),
      false,
    );
  });
}
