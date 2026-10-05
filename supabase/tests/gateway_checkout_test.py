"""Single-shop checkout reservations against disposable PostgreSQL only."""
import concurrent.futures
import pathlib
from supabase.tests import account_billing_test as billing
from supabase.tests.account_premium_test import OTHER

OWNER = billing.OWNER

MIGRATION = pathlib.Path(__file__).resolve().parents[1] / 'migrations/0097_gateway_checkout_guard.sql'


class CheckoutGuard(billing.Billing):
    def setUp(self):
        super().setUp()
        if MIGRATION.exists():
            self.sql(MIGRATION.read_text())

    def reserve(self, owner=OWNER, shop='a'):
        import json
        return json.loads(self.sql(f"select reserve_gateway_checkout('{shop}','{owner}','10',1)").stdout)

    def test_concurrent_tabs_reserve_one_checkout(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            replies = list(pool.map(lambda _: self.reserve(), range(4)))
        self.assertEqual(sum(r['reserved'] for r in replies), 1)
        self.assertEqual(self.sql("select count(*) from billing_checkouts where shop_id='a'").stdout.strip(), '1')

    def test_retry_returns_same_pending_checkout_and_paid_stays_bound(self):
        first = self.reserve()
        self.sql(f"update billing_checkouts set checkout_url='https://pay.example.com/checkout',checkout_expires_at=now()+interval '1 hour' where id='{first['checkout']['id']}'")
        retry = self.reserve()
        self.assertFalse(retry['reserved'])
        self.assertEqual(retry['checkout']['id'], first['checkout']['id'])
        self.assertEqual(retry['checkout']['checkout_url'], 'https://pay.example.com/checkout')
        self.sql(f"select fulfill_gateway_payment('{first['checkout']['id']}','99','invoice1','10')")
        self.assertEqual(self.reserve()['checkout']['subscription_id'], '99')

    def test_timeout_does_not_assume_unpaid_or_open_another_checkout(self):
        first = self.reserve()
        self.sql("update billing_checkouts set checkout_expires_at=now()-interval '1 hour'")
        self.assertFalse(self.reserve()['reserved'])
        # A delayed signed invoice remains fulfilable, rather than being lost.
        self.sql(f"select fulfill_gateway_payment('{first['checkout']['id']}','99','late-invoice','10')")

    def test_verified_failure_can_retry_and_closed_subscription_keeps_history(self):
        first = self.reserve()['checkout']['id']
        self.sql(f"select close_gateway_checkout('{first}',null)")
        second = self.reserve()['checkout']['id']
        self.assertNotEqual(first, second)
        self.sql(f"select fulfill_gateway_payment('{second}','99','invoice1','10')")
        self.assertEqual(self.sql(f"select close_gateway_checkout('{second}','99')->>'ok'").stdout.strip(), 'true')
        third = self.reserve()['checkout']['id']
        self.assertNotEqual(second, third)
        self.assertEqual(self.sql('select count(*) from billing_checkouts').stdout.strip(), '3')

    def test_other_shop_owner_cannot_reserve_or_close(self):
        self.assertIn('verified_owner_required', self.sql(f"select reserve_gateway_checkout('a','{OTHER}','10',1)", False).stderr)
        self.sql(f"set role authenticated; set request.jwt.claim.sub='{OWNER}'")
        self.assertNotEqual(self.sql("set role authenticated; select close_gateway_checkout(gen_random_uuid(),null)", False).returncode, 0)

    def test_second_initial_subscription_cannot_be_fulfilled_for_same_shop(self):
        first = '00000000-0000-4000-8000-000000000008'
        self.sql(f"insert into billing_checkouts(id,shop_id,owner_user_id,variant_id,months) values('{first}','a','{OWNER}','10',1)")
        self.sql(f"select fulfill_gateway_payment('{first}','99','invoice1','10')")
        # Reproduces an old-client checkout created before the guard existed.
        second = '00000000-0000-4000-8000-000000000009'
        self.sql(f"insert into billing_checkouts(id,shop_id,owner_user_id,variant_id,months) values('{second}','a','{OWNER}','10',1)")
        self.assertIn('duplicate_subscription', self.sql(f"select fulfill_gateway_payment('{second}','100','invoice2','10')", False).stderr)
        self.assertEqual(self.sql('select count(*) from shop_subscription_payments').stdout.strip(), '1')
