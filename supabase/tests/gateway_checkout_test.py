"""Single-shop checkout reservations against disposable PostgreSQL only."""
import concurrent.futures
import pathlib
from supabase.tests import account_billing_test as billing
from supabase.tests.account_premium_test import OTHER

OWNER = billing.OWNER

MIGRATIONS = pathlib.Path(__file__).resolve().parents[1] / 'migrations'
# 0098 comes along because 0099's reuse rule reads `provider`: the guard only
# relaxes for a card reservation, never an MMQR one.
LAYERED = ('0097_gateway_checkout_guard', '0098_mmpay_checkouts',
           '0099_reclaim_expired_checkouts')


class CheckoutGuard(billing.Billing):
    def setUp(self):
        super().setUp()
        for name in LAYERED:
            migration = MIGRATIONS / f'{name}.sql'
            if migration.exists():
                self.sql(migration.read_text())

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
        # The owner is handed the SAME reservation back, not a second one, and
        # it is still open — which is what keeps a late invoice fulfilable.
        again = self.reserve()
        self.assertTrue(again['reused'])
        self.assertEqual(again['checkout']['id'], first['checkout']['id'])
        self.assertEqual(self.sql('select count(*) from billing_checkouts').stdout.strip(), '1')
        # A delayed signed invoice remains fulfilable, rather than being lost.
        self.sql(f"select fulfill_gateway_payment('{first['checkout']['id']}','99','late-invoice','10')")

    def test_abandoned_checkout_does_not_lock_the_shop_out_forever(self):
        """The production bug: close the Lemon Squeezy tab and /renew is dead.

        There is no subscription to re-query, so the Edge Function's recovery
        branch never runs; before this, every later attempt was 409 forever.
        """
        first = self.reserve()['checkout']['id']
        self.sql(f"update billing_checkouts set checkout_url='https://pay.example.com/c',checkout_expires_at=now()-interval '2 hours' where id='{first}'")
        again = self.reserve()
        self.assertTrue(again['reserved'])
        self.assertEqual(again['checkout']['id'], first)
        # A fresh window, and no stale URL to hand back to a second tab.
        self.assertIsNone(again['checkout']['checkout_url'])
        self.assertEqual(self.sql("select count(*) from billing_checkouts where closed_at is null").stdout.strip(), '1')

    def test_reuse_waits_out_the_margin_and_never_touches_a_live_window(self):
        first = self.reserve()['checkout']['id']
        # Still inside its hour: untouched.
        self.assertFalse(self.reserve()['reserved'])
        # Expired, but only just — an invoice paid in the last seconds may
        # still be arriving, so the window is not reissued yet.
        self.sql("update billing_checkouts set checkout_expires_at=now()-interval '5 minutes'")
        self.assertFalse(self.reserve()['reserved'])
        self.sql("update billing_checkouts set checkout_expires_at=now()-interval '20 minutes'")
        self.assertTrue(self.reserve()['reserved'])
        self.assertEqual(self.sql('select count(*) from billing_checkouts').stdout.strip(), '1')
        self.assertEqual(self.sql("select id from billing_checkouts").stdout.strip(), first)

    def test_a_paid_reservation_is_never_reused_however_old(self):
        first = self.reserve()['checkout']['id']
        self.sql(f"select fulfill_gateway_payment('{first}','99','invoice1','10')")
        self.sql("update billing_checkouts set checkout_expires_at=now()-interval '10 days'")
        again = self.reserve()
        self.assertFalse(again['reserved'])
        self.assertEqual(again['checkout']['subscription_id'], '99')

    def test_reuse_keeps_the_term_it_was_reserved_for(self):
        """A late invoice names its variant, and fulfilment rejects a mismatch.

        Repurposing a dead monthly reservation as a yearly one would therefore
        lose that payment, so a changed plan keeps the old refusal instead.
        """
        import json
        self.reserve()
        self.sql("update billing_checkouts set checkout_expires_at=now()-interval '2 hours'")
        yearly = json.loads(self.sql(f"select reserve_gateway_checkout('a','{OWNER}','11',12)").stdout)
        self.assertFalse(yearly['reserved'])
        self.assertEqual(yearly['checkout']['variant_id'], '10')

    def test_an_mmqr_reservation_is_never_reused_on_age_alone(self):
        """MyanMyanPay publishes no TTL: a QR from an hour ago may still pay."""
        self.sql("insert into billing_checkouts(id,shop_id,owner_user_id,variant_id,months,provider,checkout_expires_at)"
                 f" values(gen_random_uuid(),'a','{OWNER}','mmpay:1',1,'mmpay',now()-interval '2 hours')")
        self.assertFalse(self.reserve()['reserved'])

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
