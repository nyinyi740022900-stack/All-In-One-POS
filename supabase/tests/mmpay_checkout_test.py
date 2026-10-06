"""MMQR reservations and fulfilment against disposable PostgreSQL only.

The point of putting MMQR on `billing_checkouts` rather than a table of its own
was that the one-open-checkout lock should hold BETWEEN providers. That claim
is only worth anything if something checks it, so most of what follows is about
the two providers meeting each other.
"""
import concurrent.futures
import json
import pathlib
from supabase.tests import account_billing_test as billing
from supabase.tests.account_premium_test import OTHER

OWNER = billing.OWNER
MIGRATIONS = pathlib.Path(__file__).resolve().parents[1] / 'migrations'
GUARD = MIGRATIONS / '0097_gateway_checkout_guard.sql'
MMPAY = MIGRATIONS / '0098_mmpay_checkouts.sql'


class MmqrCheckout(billing.Billing):
    def setUp(self):
        super().setUp()
        for migration in (GUARD, MMPAY):
            if migration.exists():
                self.sql(migration.read_text())

    def reserve(self, owner=OWNER, shop='a', months=1):
        return json.loads(self.sql(f"select reserve_mmpay_checkout('{shop}','{owner}',{months})").stdout)

    def reserve_card(self, owner=OWNER, shop='a'):
        return json.loads(self.sql(f"select reserve_gateway_checkout('{shop}','{owner}','10',1)").stdout)

    def test_the_server_prices_the_term_the_client_asked_for(self):
        monthly = self.reserve()['checkout']
        self.assertEqual(monthly['amount'], 20000)
        self.assertEqual(monthly['currency'], 'MMK')
        self.assertEqual(monthly['provider'], 'mmpay')
        self.sql(f"select close_mmpay_checkout('{monthly['id']}',null)")
        yearly = self.reserve(months=12)['checkout']
        self.assertEqual(yearly['amount'], 200000)
        self.assertEqual(yearly['months'], 12)

    def test_an_unsupported_term_is_refused(self):
        self.assertIn('invalid_checkout', self.sql(f"select reserve_mmpay_checkout('a','{OWNER}',3)", False).stderr)

    def test_concurrent_tabs_reserve_one_qr(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            replies = list(pool.map(lambda _: self.reserve(), range(4)))
        self.assertEqual(sum(r['reserved'] for r in replies), 1)
        self.assertEqual(self.sql("select count(*) from billing_checkouts where shop_id='a'").stdout.strip(), '1')

    def test_an_open_card_checkout_blocks_a_qr_and_the_reverse(self):
        # The whole reason MMQR rides this table: a shop must not be able to
        # hold a recurring subscription checkout and a one-off QR at once.
        card = self.reserve_card()['checkout']['id']
        held = self.reserve()
        self.assertFalse(held['reserved'])
        self.assertEqual(held['checkout']['id'], card)
        self.assertEqual(held['checkout']['provider'], 'lemonsqueezy')
        self.sql(f"select close_gateway_checkout('{card}',null)")
        qr = self.reserve()
        self.assertTrue(qr['reserved'])
        blocked = self.reserve_card()
        self.assertFalse(blocked['reserved'])
        self.assertEqual(blocked['checkout']['provider'], 'mmpay')

    def test_an_issued_order_cannot_be_closed_as_if_it_never_existed(self):
        checkout = self.reserve()['checkout']['id']
        self.sql(f"update billing_checkouts set provider_order_id='{checkout}' where id='{checkout}'")
        self.assertIn('checkout_order_mismatch', self.sql(f"select close_mmpay_checkout('{checkout}',null)", False).stderr)
        self.assertEqual(self.sql(f"select close_mmpay_checkout('{checkout}','{checkout}')->>'ok'").stdout.strip(), 'true')

    def test_a_card_row_cannot_be_closed_or_fulfilled_through_the_mmqr_path(self):
        card = self.reserve_card()['checkout']['id']
        self.assertIn('checkout_provider_mismatch', self.sql(f"select close_mmpay_checkout('{card}',null)", False).stderr)
        self.assertIn('checkout_provider_mismatch', self.sql(f"select fulfill_mmpay_payment('{card}','order1',20000)", False).stderr)

    def test_paying_a_month_grants_a_month_and_never_a_subscription(self):
        checkout = self.reserve()['checkout']['id']
        result = json.loads(self.sql(f"select fulfill_mmpay_payment('{checkout}','{checkout}',20000)").stdout)
        self.assertTrue(result['ok'])
        row = self.sql(f"select coalesce(subscription_id,'-')||' '||provider_order_id||' '||(closed_at is not null)::text from billing_checkouts where id='{checkout}'").stdout.strip()
        self.assertEqual(row, f'- {checkout} true')
        self.assertEqual(self.sql("select count(*) from shop_subscription_payments").stdout.strip(), '1')

    def test_an_underpaid_or_overpaid_order_grants_nothing(self):
        checkout = self.reserve()['checkout']['id']
        for amount in (19999, 200000, 0):
            self.assertIn('payment_amount_mismatch',
                          self.sql(f"select fulfill_mmpay_payment('{checkout}','{checkout}',{amount})", False).stderr)
        self.assertEqual(self.sql("select count(*) from shop_subscription_payments").stdout.strip(), '0')

    def test_a_tampered_reservation_amount_cannot_buy_a_year_cheaply(self):
        # The RPC re-derives the price from the stored term rather than
        # trusting the amount column, so editing the row buys nothing.
        checkout = self.reserve(months=12)['checkout']['id']
        self.sql(f"update billing_checkouts set amount=20000 where id='{checkout}'")
        self.assertIn('payment_amount_mismatch', self.sql(f"select fulfill_mmpay_payment('{checkout}','{checkout}',20000)", False).stderr)

    def test_a_redelivered_callback_grants_nothing_twice(self):
        checkout = self.reserve()['checkout']['id']
        first = json.loads(self.sql(f"select fulfill_mmpay_payment('{checkout}','{checkout}',20000)").stdout)
        second = json.loads(self.sql(f"select fulfill_mmpay_payment('{checkout}','{checkout}',20000)").stdout)
        self.assertEqual(first['expires_at'], second['expires_at'])
        self.assertEqual(self.sql("select count(*) from shop_subscription_payments").stdout.strip(), '1')

    def test_one_order_id_can_never_be_reused_by_another_row(self):
        first = self.reserve()['checkout']['id']
        self.sql(f"select fulfill_mmpay_payment('{first}','order-1',20000)")
        second = self.reserve()['checkout']['id']
        self.assertNotEqual(first, second)
        self.assertNotEqual(self.sql(f"select fulfill_mmpay_payment('{second}','order-1',20000)", False).returncode, 0)

    def test_a_stale_order_id_cannot_settle_someone_elses_row(self):
        checkout = self.reserve()['checkout']['id']
        self.sql(f"update billing_checkouts set provider_order_id='order-real' where id='{checkout}'")
        self.assertIn('checkout_order_mismatch', self.sql(f"select fulfill_mmpay_payment('{checkout}','order-other',20000)", False).stderr)

    def test_an_empty_order_id_is_not_an_identity(self):
        checkout = self.reserve()['checkout']['id']
        self.assertIn('payment_identity_required', self.sql(f"select fulfill_mmpay_payment('{checkout}','',20000)", False).stderr)

    def test_only_the_shops_own_owner_can_reserve(self):
        self.assertIn('verified_owner_required', self.sql(f"select reserve_mmpay_checkout('a','{OTHER}',1)", False).stderr)

    def test_the_rpcs_are_not_reachable_without_the_service_role(self):
        for call in ("reserve_mmpay_checkout('a','%s',1)" % OWNER,
                     "close_mmpay_checkout(gen_random_uuid(),null)",
                     "fulfill_mmpay_payment(gen_random_uuid(),'order-1',20000)"):
            self.assertNotEqual(self.sql(f"set role authenticated; select {call}", False).returncode, 0, call)

    def test_the_stale_mmpay_columns_are_gone_from_license_requests(self):
        remaining = self.sql("select count(*) from information_schema.columns "
                             "where table_name='license_requests' and column_name like 'mmpay%'").stdout.strip()
        self.assertEqual(remaining, '0')
