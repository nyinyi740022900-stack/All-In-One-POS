import 'package:supabase_flutter/supabase_flutter.dart';

/// Add and verify the replacement before removing an old Google identity.
/// A mere second unconfirmed identity is not a safe recovery route.
bool canRemoveGoogleIdentity(List<UserIdentity> identities, String identityId) {
  if (!identities.any(
    (i) => i.identityId == identityId && i.provider == 'google',
  )) {
    return false;
  }
  return identities.any(
    (i) =>
        i.identityId != identityId &&
        const ['google', 'apple', 'email'].contains(i.provider) &&
        i.identityData?['email_verified'] == true,
  );
}
