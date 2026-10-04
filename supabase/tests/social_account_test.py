"""Social authority tests on an isolated disposable PostgreSQL cluster only."""
import concurrent.futures
import pathlib
import unittest
from supabase.tests import account_premium_test as premium

NEW = '00000000-0000-0000-0000-000000000010'
STAFF = '00000000-0000-0000-0000-000000000011'
MIGRATION = pathlib.Path(__file__).resolve().parents[1] / 'migrations/0096_social_accounts.sql'

class SocialAuthority(premium.Authority):
    def setUp(self):
        super().setUp()
        self.assertTrue(MIGRATION.exists(), 'social authority migration must exist')
        self.sql(MIGRATION.read_text())
        self.sql(f"insert into auth.users(id,email) values('{NEW}','social@example.com'); insert into auth.users(id,email,raw_app_meta_data) values('{STAFF}','staff@example.com','{{\"role\":\"staff\",\"shop_id\":\"a\"}}');")

    def test_social_existing_owner_staff_and_unprovisioned(self):
        self.assertEqual(self.sql(f"select resolve_social_account('{premium.OWNER}')->>'role'").stdout.strip(), 'owner')
        self.assertEqual(self.sql(f"select resolve_social_account('{STAFF}')->>'role'").stdout.strip(), 'staff')
        self.assertEqual(self.sql(f"select resolve_social_account('{NEW}')->>'needs_shop_name'").stdout.strip(), 'true')
        self.assertIn('forbidden', self.sql(f"select create_social_account_shop('{STAFF}','Bad')",False).stderr)

    def test_social_concurrent_signup_creates_one_free_shop_without_devices_or_trial(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            results=list(pool.map(lambda _: self.sql(f"select create_social_account_shop('{NEW}','Social')->>'shop_id'"),range(8)))
        self.assertEqual(len({p.stdout.strip() for p in results}),1)
        self.assertEqual(self.sql(f"select count(*) from shop_subscriptions where owner_user_id='{NEW}' and plan='free'").stdout.strip(),'1')
        self.assertEqual(self.sql(f"select count(*) from account_trial_claims where owner_user_id='{NEW}'").stdout.strip(),'0')
        self.assertEqual(self.sql(f"select count(*) from shop_devices where user_id='{NEW}'").stdout.strip(),'0')

    def test_social_revoked_archived_or_dangling_staff_cannot_become_owner(self):
        self.sql(f"update auth.users set banned_until=now()+interval '1 year' where id='{STAFF}'")
        self.assertIn('not_authenticated',self.sql(f"select create_social_account_shop('{STAFF}','Bad')",False).stderr)
        self.sql(f"update auth.users set banned_until=null,raw_app_meta_data='{{\"role\":\"staff\",\"shop_id\":\"missing\"}}' where id='{STAFF}'")
        self.assertIn('membership_revoked',self.sql(f"select create_social_account_shop('{STAFF}','Bad')",False).stderr)
        self.sql(f"update shop_subscriptions set is_archived=true where owner_user_id='{premium.OWNER}'")
        self.assertIn('shop_archived',self.sql(f"select create_social_account_shop('{premium.OWNER}','Bad')",False).stderr)

    def test_social_provision_reuses_owner_shop_and_is_service_only(self):
        self.sql(f"select create_social_account_shop('{premium.OWNER}','Ignored')")
        self.assertEqual(self.sql(f"select count(*) from shop_subscriptions where owner_user_id='{premium.OWNER}'").stdout.strip(),'2')
        for role in ['anon','authenticated']:
            for fn in [f"resolve_social_account('{NEW}')",f"create_social_account_shop('{NEW}','Bad')",f"consume_social_reauth_proof('{NEW}','{'a'*64}',now()+interval '5 minutes')"]:
                self.assertNotEqual(self.sql(f"set role {role}; select {fn}",False).returncode,0)

    def test_social_staging_rollback_script(self):
        self.sql((MIGRATION.parents[1] / 'tests/social_account_staging.sql').read_text())

    def test_social_reauth_proof_is_consumed_once(self):
        call=f"select consume_social_reauth_proof('{NEW}','{'b'*64}',now()+interval '5 minutes')"
        self.assertEqual(self.sql(call).stdout.strip(),'t')
        self.assertEqual(self.sql(call).stdout.strip(),'f')

if __name__ == '__main__': unittest.main()
