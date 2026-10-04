"""Isolated PostgreSQL behavior tests. Never connects to a configured/cloud DB."""
import concurrent.futures, json, pathlib, shutil, subprocess, tempfile, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
MIGRATION = ROOT / 'supabase/migrations/0094_account_premium.sql'
OWNER = '00000000-0000-0000-0000-000000000001'
OTHER = '00000000-0000-0000-0000-000000000002'
class Authority(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix='account-premium-', dir='/tmp')
        cls.port = '55494'
        subprocess.run(['initdb','-D',cls.tmp+'/db','-A','trust','--no-locale'], check=True, stdout=subprocess.DEVNULL)
        subprocess.run(['pg_ctl','-D',cls.tmp+'/db','-l',cls.tmp+'/server.log','-o',f'-k {cls.tmp} -p {cls.port} -h ""','start'],check=True, stdout=subprocess.DEVNULL)
    @classmethod
    def tearDownClass(cls):
        subprocess.run(['pg_ctl','-D',cls.tmp+'/db','-m','immediate','stop'], stdout=subprocess.DEVNULL)
        shutil.rmtree(cls.tmp)
    def sql(self, text, check=True):
        p = subprocess.run(['psql','-h',self.tmp,'-p',self.port,'-d','postgres','-XAt','-v','ON_ERROR_STOP=1'], input=text, text=True, capture_output=True)
        if check and p.returncode: self.fail(p.stderr)
        return p
    def reset_legacy_schema(self):
        self.assertTrue(MIGRATION.exists(), 'account Premium authority migration must exist')
        self.sql("""
          drop schema if exists public cascade; create schema public;
          drop schema if exists auth cascade; create schema auth;
          do $$ begin create role authenticated; exception when duplicate_object then null; end $$;
          do $$ begin create role anon; exception when duplicate_object then null; end $$;
          do $$ begin create role service_role bypassrls; exception when duplicate_object then null; end $$;
          grant usage on schema public,auth to authenticated,anon,service_role;
          create table auth.users(id uuid primary key, email text, is_anonymous boolean default false, raw_app_meta_data jsonb default '{}', banned_until timestamptz);
          create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
          create function auth_shop_id() returns text language sql stable as $$ select current_setting('request.jwt.claim.shop_id',true) $$;
          create table licenses(id uuid default gen_random_uuid(), shop_id text, key text, plan text, expires_at timestamptz, activated_at timestamptz, is_deleted boolean default false, device_id text, last_verified_at timestamptz, shop_name text);
          create table org_branches(owner_user_id uuid, shop_id text, label text, created_at timestamptz default now(), last_active_at timestamptz default now(), unique(owner_user_id,shop_id));
          alter table org_branches enable row level security;
          create policy org_branches_owner on org_branches for all to authenticated using(owner_user_id=auth.uid()) with check(owner_user_id=auth.uid());
          grant all on org_branches to authenticated;
          create table shop_device_allowance(shop_id text, extra_slots int, extras_expires_at timestamptz);
        """)
    def setUp(self):
        self.reset_legacy_schema()
        self.sql(MIGRATION.read_text())
        self.sql(f"insert into auth.users(id,email) values ('{OWNER}','a@example.com'),('{OTHER}','b@example.com'); select create_account_shop('{OWNER}','a','A','d1'); select create_account_shop('{OWNER}','branch','Branch',null); select create_account_shop('{OTHER}','b','B','b1');")
    def test_deleted_shop_trial_history_still_blocks_retained_owner_accounts(self):
        self.reset_legacy_schema()
        owners = ['3476821d-e7ab-4fc3-966b-ad628fc52e1d', 'af47495e-4505-40cb-aefb-bc0fbf0be729']
        for owner in owners:
            self.sql(f"insert into auth.users(id,email,raw_app_meta_data) values ('{owner}','retained-{owner}@example.com','{{\"role\":\"owner\"}}')")
        self.sql(MIGRATION.read_text())
        self.assertEqual(self.sql("select count(*) from shop_subscriptions").stdout.strip(), '0')
        for index, owner in enumerate(owners):
            self.sql(f"select create_account_shop('{owner}','new-{index}','New shop',null)")
            self.assertIn('trial_already_used',self.sql(f"select start_account_trial('{owner}','new-{index}')",False).stderr)
        self.assertEqual(self.sql("select count(*) from account_trial_claims where shop_id='shop-5bd659ab60b5'").stdout.strip(), '2')

    def test_orphan_subscription_cannot_receive_paid_renewal(self):
        self.sql("insert into shop_subscriptions(shop_id,shop_name) values('orphan','Legacy shop')")
        self.assertIn('ownership_verification_required',self.sql("select renew_shop_subscription('orphan',1,'orphan-payment')",False).stderr)
        self.assertEqual(self.sql("select plan from shop_subscriptions where shop_id='orphan'").stdout.strip(),'free')
        self.assertEqual(self.sql("select count(*) from shop_subscription_payments where payment_id='orphan-payment'").stdout.strip(),'0')

    def test_failed_trial_device_registration_rolls_back_claim(self):
        self.sql(f"insert into shop_devices(shop_id,device_id,user_id) select 'a','d'||n,'{OWNER}'::uuid from generate_series(2,3) n")
        failed=self.sql(f"select start_account_trial('{OWNER}','a','fourth',false,null)",False)
        self.assertIn('device_limit_reached',failed.stderr)
        self.assertEqual(self.sql(f"select count(*) from account_trial_claims where owner_user_id='{OWNER}'").stdout.strip(),'0')
        self.assertEqual(self.sql("select plan from shop_subscriptions where shop_id='a'").stdout.strip(),'free')
        self.sql(f"select start_account_trial('{OWNER}','a','d1',false,null)")
        self.assertEqual(self.sql(f"select count(*) from account_trial_claims where owner_user_id='{OWNER}'").stdout.strip(),'1')

    def test_free_device_replacement_requires_owner_release_and_explicit_signin(self):
        self.sql(f"select register_shop_device('{OWNER}','a','d1')")
        self.assertIn('free_device_replacement_required',self.sql(f"select register_shop_device('{OWNER}','a','new',true)",False).stderr)
        self.sql(f"select release_shop_device('{OWNER}','a','d1')")
        self.assertIn('free_device_replacement_required',self.sql(f"select register_shop_device('{OWNER}','a','new',false)",False).stderr)
        self.sql(f"select register_shop_device('{OWNER}','a','new',true)")
        self.assertEqual(self.sql("select free_device_id from shop_subscriptions where shop_id='a'").stdout.strip(),'new')
        self.assertEqual(self.sql("select count(*) from shop_devices where shop_id='a' and released_at is null").stdout.strip(),'1')

    def test_trial_once_per_owner_and_cross_shop_denied(self):
        self.sql(f"select start_account_trial('{OWNER}','a')")
        p = self.sql(f"select start_account_trial('{OWNER}','branch')", False)
        self.assertIn('trial_already_used',p.stderr)
        p = self.sql(f"select start_account_trial('{OTHER}','a')", False)
        self.assertIn('membership_revoked',p.stderr)
        self.assertEqual(self.sql(f"select expires_at=started_at+interval '2 months' from account_trial_claims where owner_user_id='{OWNER}'").stdout.strip(),'t')
    def test_concurrent_claims_allow_only_three_and_release_is_sticky(self):
        self.sql(f"select start_account_trial('{OWNER}','a')")
        def claim(i): return self.sql(f"select register_shop_device('{OWNER}','a','d{{i}}')".replace('{i}',str(i)),False)
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool: results=list(pool.map(claim,range(2,10)))
        self.assertEqual(sum(p.returncode==0 for p in results),2)
        self.assertEqual(self.sql("select count(*) from shop_devices where shop_id='a' and released_at is null").stdout.strip(),'3')
        self.sql(f"select release_shop_device('{OWNER}','a','d1')")
        self.assertIn('device_released',self.sql(f"select register_shop_device('{OWNER}','a','d1')",False).stderr)
        self.sql(f"select register_shop_device('{OWNER}','a','replacement')")
    def test_renewal_is_idempotent_and_grace_anchor(self):
        self.sql("update shop_subscriptions set plan='monthly',expires_at=now()-interval '2 days' where shop_id='a'")
        self.sql("select renew_shop_subscription('a',1,'payment-1')")
        self.assertEqual(self.sql("select abs(extract(epoch from (expires_at-(now()-interval '2 days'+interval '1 month'))))<5 from shop_subscriptions where shop_id='a'").stdout.strip(),'t')
        self.assertEqual(self.sql("select renew_shop_subscription('a',1,'payment-1')->>'duplicate'").stdout.strip(),'true')
        self.assertIn('payment_conflict', self.sql("select renew_shop_subscription('b',1,'payment-1')",False).stderr)
        self.sql("update shop_subscriptions set expires_at=now()-interval '15 days' where shop_id='b'; select renew_shop_subscription('b',12,'year-1')")
        self.assertEqual(self.sql("select abs(extract(epoch from (expires_at-(now()+interval '12 months'))))<5 from shop_subscriptions where shop_id='b'").stdout.strip(),'t')
    def test_rls_and_service_only_mutations(self):
        self.sql(f"set role authenticated; set request.jwt.claim.sub='{OWNER}'; select * from shop_subscriptions;")
        self.assertEqual(self.sql(f"set role authenticated; set request.jwt.claim.sub='{OTHER}'; select count(*) from shop_subscriptions where shop_id='a'").stdout.strip().splitlines()[-1],'0')
        for statement in [f"insert into org_branches(owner_user_id,shop_id) values('{OTHER}','a')", "update shop_subscriptions set plan='monthly'", f"select start_account_trial('{OWNER}','a')"]:
            self.assertNotEqual(self.sql('set role authenticated; '+statement,False).returncode,0)
    def test_legacy_attach_requires_trusted_owner_and_consumes_historical_trial(self):
        legacy = '00000000-0000-0000-0000-000000000003'
        self.sql(f"insert into auth.users(id,is_anonymous,raw_app_meta_data) values('{legacy}',true,'{{\"shop_id\":\"legacy\",\"role\":\"owner\"}}'); insert into shop_subscriptions(shop_id) values('legacy'); insert into licenses(shop_id,plan,expires_at) values('legacy','trial',now()-interval '1 year');")
        self.assertIn('ownership_verification_required',self.sql(f"select attach_legacy_shop_owner('{OTHER}','{OWNER}','legacy')",False).stderr)
        self.sql(f"select attach_legacy_shop_owner('{legacy}','{OWNER}','legacy')")
        self.assertIn('trial_already_used',self.sql(f"select start_account_trial('{OWNER}','branch')",False).stderr)
    def test_staff_cannot_start_trial_or_release_owner_device(self):
        staff = '00000000-0000-0000-0000-000000000004'
        self.sql(f"insert into auth.users(id,email,raw_app_meta_data) values('{staff}','staff@example.com','{{\"shop_id\":\"a\",\"role\":\"staff\"}}'); select start_account_trial('{OWNER}','a'); select register_shop_device('{staff}','a','staff-device');")
        self.assertIn('membership_revoked', self.sql(f"select start_account_trial('{staff}','a')",False).stderr)
        self.assertIn('forbidden',self.sql(f"select release_shop_device('{staff}','a','d1')",False).stderr)
        self.sql(f"update auth.users set banned_until=now()+interval '1 year' where id='{staff}'")
        self.assertIn('membership_revoked',self.sql(f"select register_shop_device('{staff}','a','staff-device')",False).stderr)
    def test_business_rls_requires_premium_membership_and_active_session_device(self):
        session = '00000000-0000-0000-0000-000000000099'
        self.sql("create table business_rows(shop_id text, note text); alter table business_rows enable row level security; create policy shop_isolation on business_rows for all to authenticated using(shop_id=auth_shop_id()) with check(shop_id=auth_shop_id()); grant all on business_rows to authenticated; insert into business_rows values('a','existing');")
        claims = f"set role authenticated; set request.jwt.claim.shop_id='a'; set request.jwt.claim.sub='{OWNER}'; set request.jwt.claims='{{\"sub\":\"{OWNER}\",\"session_id\":\"{session}\",\"app_metadata\":{{\"shop_id\":\"a\"}}}}'; "
        self.assertEqual(self.sql(claims+"select count(*) from business_rows").stdout.strip().splitlines()[-1],'0')
        self.assertNotEqual(self.sql(claims+"insert into business_rows values('a','denied')",False).returncode,0)
        self.sql(f"select start_account_trial('{OWNER}','a'); select register_shop_device('{OWNER}','a','d1',false,'{session}');")
        self.assertEqual(self.sql(claims+"select count(*) from business_rows").stdout.strip().splitlines()[-1],'1')
        self.sql(claims+"insert into business_rows values('a','allowed')")
        self.sql("update shop_subscriptions set expires_at=now()-interval '15 days' where shop_id='a'")
        self.assertEqual(self.sql(claims+"select count(*) from business_rows").stdout.strip().splitlines()[-1],'0')
        self.sql("select renew_shop_subscription('a',1,'restore-sync')")
        self.assertEqual(self.sql(claims+"select count(*) from business_rows").stdout.strip().splitlines()[-1],'2')
        self.sql(f"select release_shop_device('{OWNER}','a','d1')")
        self.assertEqual(self.sql(claims+"select count(*) from business_rows").stdout.strip().splitlines()[-1],'0')
    def test_migration_preserves_paid_expiry_devices_and_consumed_trials(self):
        self.reset_legacy_schema()
        self.sql(f"insert into auth.users(id,email,raw_app_meta_data) values('{OWNER}','owner@example.com','{{\"role\":\"owner\",\"shop_id\":\"legacy\"}}'); insert into org_branches(owner_user_id,shop_id) values('{OWNER}','legacy'); insert into licenses(shop_id,plan,expires_at,device_id,is_deleted) values('legacy','monthly','2030-01-31Z','old1',false),('legacy','yearly','2031-01-31Z','old2',false),('legacy','trial','2020-01-31Z',null,true),('archived','yearly','2040-01-31Z','removed',true); ")
        self.sql(MIGRATION.read_text())
        self.assertEqual(self.sql("select plan || '|' || extract(year from expires_at)::text from shop_subscriptions where shop_id='legacy'").stdout.strip(),'yearly|2031')
        self.assertEqual(self.sql("select count(*) from shop_devices where shop_id='legacy'").stdout.strip(),'2')
        self.assertEqual(self.sql("select is_archived from shop_subscriptions where shop_id='archived'").stdout.strip(),'t')
        self.assertEqual(self.sql(f"select count(*) from account_trial_claims where owner_user_id='{OWNER}'").stdout.strip(),'1')
    def test_preflight_refuses_untrusted_links_and_paid_allowances(self):
        self.reset_legacy_schema()
        self.sql(f"insert into auth.users(id,email) values('{OWNER}','owner@example.com'); insert into org_branches(owner_user_id,shop_id) values('{OWNER}','unproven');")
        self.assertIn('unverified or ambiguous ownership',self.sql(MIGRATION.read_text(),False).stderr)
        report=json.loads(self.sql((ROOT/'supabase/tests/account_premium_preflight.sql').read_text()).stdout.strip())
        self.assertEqual(len(report['unverified_branch_owners']),1)
        self.sql("delete from org_branches; insert into shop_device_allowance values('paid',1,now()+interval '1 month')")
        self.assertIn('paid allowance',self.sql(MIGRATION.read_text(),False).stderr)
    def test_concurrent_trial_and_payment_retries_commit_once(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            trials=list(pool.map(lambda shop:self.sql(f"select start_account_trial('{OWNER}','{shop}')",False),['a','branch']))
        self.assertEqual(sum(p.returncode==0 for p in trials),1)
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
            payments=list(pool.map(lambda _:self.sql("select renew_shop_subscription('a',1,'same-payment')->>'duplicate'"),range(6)))
        self.assertEqual(sum(p.stdout.strip()=='false' for p in payments),1)
        self.assertEqual(self.sql("select count(*) from shop_subscription_payments").stdout.strip(),'1')
    def test_legacy_rpcs_are_not_executable_by_any_application_role(self):
        self.reset_legacy_schema()
        self.sql("create function create_license(text,text,int,text) returns text language sql as $$ select 'unsafe'::text $$; create function grant_extra_device_slot(text) returns text language sql as $$ select 'unsafe'::text $$; grant execute on function create_license(text,text,int,text),grant_extra_device_slot(text) to service_role,authenticated,anon;")
        self.sql(MIGRATION.read_text())
        for role in ['service_role','authenticated','anon']:
            self.assertNotEqual(self.sql(f"set role {role}; select create_license('a','monthly',1,'A')",False).returncode,0)
            self.assertNotEqual(self.sql(f"set role {role}; select grant_extra_device_slot('a')",False).returncode,0)
    def test_free_cannot_claim_second_device(self):
        self.assertIn('free_device_replacement_required',self.sql(f"select register_shop_device('{OWNER}','a','another')",False).stderr)
if __name__=='__main__': unittest.main()
