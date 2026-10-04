"""Transactional billing tests against a disposable PostgreSQL instance."""
import pathlib, unittest
from supabase.tests.account_premium_test import Authority, OWNER
MIGRATION = pathlib.Path(__file__).resolve().parents[1] / 'migrations/0095_account_billing.sql'

class Billing(Authority):
    def setUp(self):
        super().setUp()
        self.assertTrue(MIGRATION.exists(), 'account billing migration must exist')
        self.sql('''create table license_requests(id text primary key, shop_id text, shop_name text, plan text, months int, amount int, status text, payment_status text, paid_at timestamptz, updated_at timestamptz, reject_reason text); alter table license_requests enable row level security;''')
        self.sql("""create schema if not exists storage;
          create table if not exists storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);
          alter table storage.objects enable row level security;
          create or replace function storage.foldername(text) returns text[] language sql immutable as $$select string_to_array($1,'/')$$;
          grant usage on schema storage to authenticated,anon;
          grant select,insert on storage.objects to authenticated,anon;
        """)
        self.sql(MIGRATION.read_text())
    def request(self, id='r1', amount=20000):
        self.sql(f"insert into license_requests(id,shop_id,shop_name,owner_user_id,plan,months,amount,status) values('{id}','a','A','{OWNER}','monthly',1,{amount},'pending')")
    def test_fulfill_retry_and_rejection_do_not_extend_again(self):
        self.request()
        self.sql("select fulfill_account_payment('r1')")
        expiry = self.sql("select expires_at from shop_subscriptions where shop_id='a'").stdout
        self.assertEqual(self.sql("select fulfill_account_payment('r1')->>'duplicate'").stdout.strip(),'true')
        self.assertEqual(self.sql("select expires_at from shop_subscriptions where shop_id='a'").stdout, expiry)
        self.assertIn('request_not_pending', self.sql("select reject_account_payment('r1','no')",False).stderr)
    def test_invalid_price_or_unverified_request_never_fulfills(self):
        self.request(amount=1)
        self.assertIn('invalid_request_price',self.sql("select fulfill_account_payment('r1')",False).stderr)
        self.sql("update license_requests set amount=20000,owner_user_id=null")
        self.assertIn('verified_owner_required', self.sql("select fulfill_account_payment('r1')",False).stderr)
        self.assertEqual(self.sql("select count(*) from shop_subscription_payments").stdout.strip(),'0')
    def test_payment_and_request_commit_together(self):
        self.request()
        self.sql("create function fail_receipt() returns trigger language plpgsql as $$begin raise exception 'receipt unavailable'; end$$; create trigger fail_receipt before update on license_requests for each row execute function fail_receipt();")
        self.assertIn('receipt unavailable',self.sql("select fulfill_account_payment('r1')",False).stderr)
        self.assertEqual(self.sql("select count(*) from shop_subscription_payments").stdout.strip(),'0')
    def test_gateway_invoice_duplicate_and_subscription_binding(self):
        self.sql(f"insert into billing_checkouts(id,shop_id,owner_user_id,variant_id,months) values('00000000-0000-4000-8000-000000000001','a','{OWNER}','variant-1',1)")
        args="'00000000-0000-4000-8000-000000000001','sub1','invoice1','variant-1'"
        self.sql(f"select fulfill_gateway_payment({args})")
        self.assertEqual(self.sql(f"select fulfill_gateway_payment({args})->>'duplicate'").stdout.strip(),'true')
        self.assertIn('checkout_subscription_mismatch',self.sql("select fulfill_gateway_payment('00000000-0000-4000-8000-000000000001','sub2','invoice2','variant-1')",False).stderr)
    def test_lapsed_owner_can_upload_billing_proof_but_cannot_read_another_shop(self):
        self.sql(f"set role authenticated; set request.jwt.claim.sub='{OWNER}'; insert into storage.objects(bucket_id,name) values('payment-proofs','_admin/{OWNER}/proof.png')")
        self.sql("insert into storage.objects(bucket_id,name) values('payment-proofs','b/proof.png')")
        result=self.sql(f"set role authenticated; set request.jwt.claim.sub='{OWNER}'; select count(*) from storage.objects where name='b/proof.png'")
        self.assertEqual(result.stdout.strip().splitlines()[-1],'0')

    def test_missing_payment_amount_is_rejected(self):
        self.request()
        self.sql("update license_requests set amount=null")
        self.assertIn('invalid_request_price',self.sql("select fulfill_account_payment('r1')",False).stderr)

    def test_archive_refuses_paid_subscription_but_allows_trial(self):
        self.sql("select renew_shop_subscription('a',1,'paid1')")
        self.assertIn('shop_is_paid',self.sql("select archive_shop_subscription('a',true)",False).stderr)
        self.sql(f"select start_account_trial('{OWNER}','branch'); select archive_shop_subscription('branch',true)")
        self.assertEqual(self.sql("select is_archived from shop_subscriptions where shop_id='branch'").stdout.strip(),'t')

    def test_simultaneous_manual_approval_grants_one_term(self):
        import concurrent.futures
        self.request()
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            results=list(pool.map(lambda _: self.sql("select fulfill_account_payment('r1')"),range(4)))
        self.assertEqual(len(results),4)
        self.assertEqual(self.sql("select count(*) from shop_subscription_payments where payment_id='manual:r1'").stdout.strip(),'1')

    def test_client_cannot_invoke_billing_mutations(self):
        self.assertNotEqual(self.sql("set role authenticated; select fulfill_account_payment('r1')",False).returncode,0)

    def test_owner_deletion_preserves_unowned_billing_audit_without_fk_failure(self):
        self.request()
        self.sql(f"insert into billing_checkouts(id,shop_id,owner_user_id,variant_id,months) values('00000000-0000-4000-8000-000000000001','a','{OWNER}','variant-1',1)")
        self.sql(f"delete from auth.users where id='{OWNER}'")
        self.assertEqual(self.sql("select count(*) from billing_checkouts where owner_user_id is null").stdout.strip(),'1')
        self.assertEqual(self.sql("select count(*) from license_requests where owner_user_id is null").stdout.strip(),'1')
        self.assertIn('verified_owner_required',self.sql("select fulfill_account_payment('r1')",False).stderr)
        self.assertIn('verified_owner_required',self.sql("select fulfill_gateway_payment('00000000-0000-4000-8000-000000000001','sub','invoice','variant-1')",False).stderr)

if __name__=='__main__': unittest.main()
