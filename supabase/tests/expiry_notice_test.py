"""Expiry-reminder claiming, against disposable PostgreSQL only.

The property that matters is that an owner is never mailed the same reminder
twice — a duplicate reminder is worse than one arriving a day late, which is
why claiming happens before sending.
"""
import pathlib
from supabase.tests import account_billing_test as billing
from supabase.tests.account_premium_test import OTHER

OWNER = billing.OWNER
MIGRATIONS = pathlib.Path(__file__).resolve().parents[1] / 'migrations'
LAYERED = ('0097_gateway_checkout_guard', '0098_mmpay_checkouts',
           '0099_reclaim_expired_checkouts', '0100_reuse_across_plan_change',
           '0101_expiry_notices')


class ExpiryNotices(billing.Billing):
    def setUp(self):
        super().setUp()
        for name in LAYERED:
            m = MIGRATIONS / f'{name}.sql'
            if m.exists():
                self.sql(m.read_text())

    def set_expiry(self, days, plan='monthly', shop='a'):
        """Put the shop's expiry `days` whole Yangon-days from today."""
        self.sql(f"""update shop_subscriptions
                        set plan='{plan}',
                            expires_at = ((date(now() at time zone 'Asia/Yangon') + {days})
                                          ::timestamp at time zone 'Asia/Yangon') + interval '9 hours'
                      where shop_id='{shop}'""")

    def claim(self):
        return self.sql("select shop_id||':'||days_left from claim_expiry_notices()").stdout.split()

    def test_warns_at_seven_three_and_one_but_not_between(self):
        for days, expect in [(7, True), (6, False), (3, True), (2, False), (1, True), (0, False)]:
            self.sql('delete from shop_expiry_notices')
            self.set_expiry(days)
            got = bool(self.claim())
            self.assertEqual(got, expect, f'{days} days left -> claimed={got}')

    def test_the_same_reminder_is_never_claimed_twice(self):
        self.set_expiry(7)
        self.assertEqual(self.claim(), ['a:7'])
        self.assertEqual(self.claim(), [], 'a second run must claim nothing')

    def test_renewing_lets_the_next_cycle_warn_again(self):
        """The stamp carries the expiry, so a renewal resets nothing by hand."""
        self.set_expiry(7)
        self.assertEqual(self.claim(), ['a:7'])
        # Still the same expiry seven days out: already warned, stays quiet.
        self.assertEqual(self.claim(), [])
        # A renewal moves expires_at. Seven days before the NEW date is a
        # different stamp, so it warns again with nothing reset anywhere.
        self.sql("update shop_subscriptions set expires_at = expires_at + interval '30 days' where shop_id='a'")
        self.assertEqual(self.claim(), [], 'now 37 days out, nothing due')
        self.set_expiry(7)
        self.sql("update shop_subscriptions set expires_at = expires_at + interval '1 second' where shop_id='a'")
        self.assertEqual(self.claim(), ['a:7'])

    def test_a_lapsed_shop_is_told_once_the_day_after(self):
        self.set_expiry(-1)
        self.assertEqual(self.claim(), ['a:-1'])
        self.assertEqual(self.claim(), [])
        # Not every day forever afterwards.
        self.sql('delete from shop_expiry_notices')
        self.set_expiry(-2)
        self.assertEqual(self.claim(), [])

    def test_free_and_archived_shops_are_never_mailed(self):
        self.set_expiry(7, plan='free')
        self.assertEqual(self.claim(), [], 'Free has no expiry to warn about')
        self.set_expiry(7, plan='monthly')
        self.sql("update shop_subscriptions set is_archived=true where shop_id='a'")
        self.assertEqual(self.claim(), [])

    def test_a_release_lets_a_failed_send_be_retried(self):
        self.set_expiry(3)
        self.assertEqual(self.claim(), ['a:3'])
        stamp = self.sql("select stamp from shop_expiry_notices where shop_id='a'").stdout.strip()
        self.sql(f"select release_expiry_notice('a','{stamp}')")
        self.assertEqual(self.claim(), ['a:3'], 'a released claim is due again')

    def test_claiming_is_service_role_only(self):
        self.assertNotEqual(
            self.sql("set role authenticated; select claim_expiry_notices()", False).returncode, 0)
        self.assertNotEqual(
            self.sql("set role anon; select release_expiry_notice('a','x')", False).returncode, 0)
