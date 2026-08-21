import '../../l10n/app_localizations.dart';

/// Shared mapping so onboarding, daily gate, Account, and License never
/// disagree on the same error code (the "Something went wrong" vs "No
/// internet" split is what made a failed new-install sign-in look like two
/// different bugs).
String accountActionErrorMessage(AppLocalizations l, String? code) =>
    switch (code) {
      'email_taken' => l.accountEmailTaken,
      'no_backend' || 'network_error' => l.commonNetworkError,
      'not_activated' => l.accountSignInNoShop,
      'not_authenticated' => l.accountSignInSessionFailed,
      'not_found' => l.licenseRenewNotFound,
      'pending_sync' => l.accountPendingSync,
      'stuck_outbox' => l.branchesSwitchBlockedStuckOutbox,
      'trial_already_used' => l.accountTrialAlreadyUsed,
      'wrong_password' => l.accountDeleteWrongPassword,
      'forbidden' => l.accountDeleteOwnerOnly,
      'invalid_credentials' || 'auth_failed' => l.accountInvalidCredentials,
      'payment_required' => l.accountSignInDeviceLimit,
      _ => l.accountActionFailed,
    };
