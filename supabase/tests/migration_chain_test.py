"""Rehearses the whole migration chain the way `supabase db push` applies it.

The other suites here bootstrap a synthetic 0093-shaped schema and exercise one
migration. That leaves the thing a real cutover actually does untested: apply
0001..NNNN in order to a database that has only the platform's own objects, and
then carry existing shops across. Both failures this catches are silent until
deploy time — a migration that only works because an earlier test fixture
happened to create a column, and a backfill that drops a shop on the floor.

Never connects to a configured or cloud database: every test runs against a
disposable cluster in /tmp that is initdb'd and thrown away.
"""
import pathlib, shutil, subprocess, tempfile, unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
MIGRATIONS = sorted((ROOT / 'supabase/migrations').glob('[0-9]*.sql'))
ACCOUNT_MIGRATIONS = ('0094_account_premium', '0095_account_billing', '0096_social_accounts',
                      '0097_gateway_checkout_guard', '0098_mmpay_checkouts')

# What a hosted Supabase project already has before the first project migration
# runs. This is a stand-in for the platform, not a project migration: only the
# objects the chain actually touches (auth users/uid, storage buckets/objects,
# the three request roles, the realtime publication).
PLATFORM = """
create extension if not exists "pgcrypto";
do $$ begin create role anon nologin; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated nologin; exception when duplicate_object then null; end $$;
do $$ begin create role service_role nologin bypassrls; exception when duplicate_object then null; end $$;
create schema if not exists auth;
create schema if not exists storage;
grant usage on schema auth, storage to anon, authenticated, service_role;
create table auth.users(
  id uuid primary key default gen_random_uuid(), email text,
  is_anonymous boolean default false, raw_app_meta_data jsonb default '{}'::jsonb,
  raw_user_meta_data jsonb default '{}'::jsonb, banned_until timestamptz,
  created_at timestamptz default now());
create function auth.uid() returns uuid language sql stable as
  $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create function auth.jwt() returns jsonb language sql stable as
  $$ select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb) $$;
create table storage.buckets(
  id text primary key, name text not null, public boolean default false,
  file_size_limit bigint, allowed_mime_types text[], owner uuid,
  created_at timestamptz default now(), updated_at timestamptz default now());
create table storage.objects(
  id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets(id),
  name text, owner uuid, metadata jsonb,
  created_at timestamptz default now(), updated_at timestamptz default now());
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as
  $$ select (select parts[1:array_length(parts, 1) - 1]
             from (select string_to_array(name, '/') as parts) s) $$;
grant all on all tables in schema auth, storage to service_role;
do $$ begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime')
  then create publication supabase_realtime; end if;
end $$;
"""

# A 0093-era state shaped like production: several shops across paid/lapsed/
# trial/free/archived, one legacy shop with no owner account, devices both live
# and superseded, plus the two owner accounts that were retained when MM SHOP
# was deleted on 2026-10-04.
OWNER_A = '11111111-1111-1111-1111-111111111111'
OWNER_B = '22222222-2222-2222-2222-222222222222'
OWNER_C = '33333333-3333-3333-3333-333333333333'
MM_OWNERS = ('3476821d-e7ab-4fc3-966b-ad628fc52e1d', 'af47495e-4505-40cb-aefb-bc0fbf0be729')
MM_SHOP = 'shop-5bd659ab60b5'
LEGACY = f"""
insert into auth.users(id,email,raw_app_meta_data) values
 ('{OWNER_A}','a@example.com','{{"role":"owner","shop_id":"shop-a"}}'),
 ('{OWNER_B}','b@example.com','{{"role":"owner","shop_id":"shop-b"}}'),
 ('{OWNER_C}','c@example.com','{{"role":"owner","shop_id":"shop-c"}}'),
 ('{MM_OWNERS[0]}','mm1@example.com','{{"role":"owner"}}'),
 ('{MM_OWNERS[1]}','mm2@example.com','{{"role":"owner"}}');
insert into licenses(shop_id,key,plan,expires_at,activated_at,is_deleted,device_id,shop_name,last_verified_at) values
 ('shop-a','K-A1','monthly','2026-11-01T00:00:00Z','2026-09-01T00:00:00Z',false,'dev-a1','Shop A','2026-10-01T00:00:00Z'),
 ('shop-a','K-A2','monthly','2026-10-20T00:00:00Z','2026-09-15T00:00:00Z',false,'dev-a2','Shop A','2026-10-02T00:00:00Z'),
 ('shop-a','K-A0','monthly','2026-08-01T00:00:00Z','2026-07-01T00:00:00Z',true ,'dev-old','Shop A',null),
 ('shop-b','K-B1','yearly','2026-09-20T00:00:00Z','2025-09-20T00:00:00Z',false,'dev-b1','Shop B','2026-09-19T00:00:00Z'),
 ('shop-c','K-C1','trial','2026-06-01T00:00:00Z','2026-04-01T00:00:00Z',false,'dev-c1','Shop C','2026-05-30T00:00:00Z'),
 ('shop-d','K-D1','monthly','2026-12-01T00:00:00Z','2026-09-01T00:00:00Z',false,'dev-d1','Shop D',null),
 ('shop-e','K-E1','free','1970-01-01T00:00:00Z','2026-08-01T00:00:00Z',false,null,'Shop E',null),
 ('shop-f','K-F1','monthly','2026-07-01T00:00:00Z','2026-05-01T00:00:00Z',true,'dev-f1','Shop F',null),
 ('shop-g','K-G1','trial','2026-03-01T00:00:00Z','2026-01-01T00:00:00Z',false,'dev-g1','Shop G',null);
insert into org_branches(owner_user_id,shop_id,label) values
 ('{OWNER_A}','shop-a','Shop A'),('{OWNER_B}','shop-b','Shop B'),('{OWNER_C}','shop-c','Shop C');
"""
LEGACY_SHOPS = 7


class MigrationChain(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix='chain-', dir='/tmp')  # short path: the socket has a 103-byte limit
        cls.port = '55497'
        subprocess.run(['initdb', '-D', cls.tmp + '/db', '-A', 'trust', '--no-locale'],
                       check=True, stdout=subprocess.DEVNULL)
        subprocess.run(['pg_ctl', '-D', cls.tmp + '/db', '-l', cls.tmp + '/server.log',
                        '-o', f'-k {cls.tmp} -p {cls.port} -h ""', '-w', 'start'],
                       check=True, stdout=subprocess.DEVNULL)

    @classmethod
    def tearDownClass(cls):
        subprocess.run(['pg_ctl', '-D', cls.tmp + '/db', '-m', 'immediate', 'stop'], stdout=subprocess.DEVNULL)
        shutil.rmtree(cls.tmp)

    def sql(self, text, check=True):
        p = subprocess.run(['psql', '-h', self.tmp, '-p', self.port, '-d', 'postgres', '-XAt',
                            '-v', 'ON_ERROR_STOP=1'], input=text, text=True, capture_output=True)
        if check and p.returncode:
            self.fail(p.stderr)
        return p

    def value(self, query):
        return self.sql(query).stdout.strip()

    def fresh_platform(self):
        """An empty project: platform objects only, no project migration yet."""
        self.sql("""
          drop schema if exists public cascade; create schema public;
          drop schema if exists auth cascade; drop schema if exists storage cascade;
          drop publication if exists supabase_realtime;
          grant usage on schema public to public;
        """)
        self.sql(PLATFORM)

    def apply(self, migrations, check=True):
        """Apply each file on its own, exactly as a push walks the directory."""
        for path in migrations:
            p = self.sql(path.read_text(), check=False)
            if p.returncode:
                if check:
                    self.fail(f'{path.name} failed to apply: {p.stderr}')
                return path, p.stderr
        return None, ''

    def setUp(self):
        self.fresh_platform()

    def test_whole_chain_applies_to_an_empty_project(self):
        self.apply(MIGRATIONS)
        self.assertGreater(int(self.value("select count(*) from pg_tables where schemaname='public'")), 30)
        # Every synced table must end up with RLS on; a table with RLS and no
        # policy at all is server-only and allowed, a table without RLS is not.
        self.assertEqual(self.value("""
          select coalesce(string_agg(relname, ', ' order by relname), '')
          from pg_class c join pg_namespace n on n.oid = c.relnamespace
          where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity
        """), '', 'these public tables ship without row level security')
        self.assertEqual(self.value("""
          select coalesce(string_agg(polname || ' on ' || relname, ', '), '')
          from pg_policy p join pg_class c on c.oid = p.polrelid where polname ilike '%dev_open%'
        """), '', 'a dev-open policy survived the chain')
        for table in ('shop_subscriptions', 'shop_devices', 'account_trial_claims'):
            self.assertEqual(self.value(f"select to_regclass('public.{table}') is not null"), 't')

    def test_chain_carries_every_existing_shop_across(self):
        self.apply([m for m in MIGRATIONS if m.stem not in ACCOUNT_MIGRATIONS])
        self.sql(LEGACY)
        self.apply([m for m in MIGRATIONS if m.stem in ACCOUNT_MIGRATIONS])

        self.assertEqual(self.value('select count(*) from shop_subscriptions'), str(LEGACY_SHOPS))
        self.assertEqual(self.value("select plan from shop_subscriptions where shop_id='shop-a'"), 'monthly')
        self.assertEqual(self.value("""select to_char(expires_at at time zone 'UTC','YYYY-MM-DD')
                                       from shop_subscriptions where shop_id='shop-a'"""), '2026-11-01')
        self.assertEqual(self.value("select owner_user_id from shop_subscriptions where shop_id='shop-a'"), OWNER_A)
        # Live devices come across; the superseded (deleted) row's device does not.
        self.assertEqual(self.value("select count(*) from shop_devices where shop_id='shop-a'"), '2')
        self.assertEqual(self.value("select plan from shop_subscriptions where shop_id='shop-b'"), 'yearly')
        self.assertEqual(self.value("select plan from shop_subscriptions where shop_id='shop-c'"), 'trial')
        self.assertEqual(self.value("select plan from shop_subscriptions where shop_id='shop-e'"), 'free')
        self.assertEqual(self.value("select is_archived from shop_subscriptions where shop_id='shop-f'"), 't')
        # A legacy key-only shop has no owner account, and must not be renewable.
        self.assertEqual(self.value("select owner_user_id is null from shop_subscriptions where shop_id='shop-d'"), 't')
        self.assertIn('ownership_verification_required',
                      self.sql("select renew_shop_subscription('shop-d',1,'pay-d')", False).stderr)
        self.assertEqual(self.value('select count(*) from shop_subscriptions where revision <> 1'), '0')
        # A historical trial stays consumed, so no shop gets a second free term.
        self.assertEqual(self.value(f"select count(*) from account_trial_claims where owner_user_id='{OWNER_C}'"), '1')
        self.assertIn('trial_already_used', self.sql(f"select start_account_trial('{OWNER_C}','shop-c')", False).stderr)
        # Deleting MM SHOP kept its owners: their trial is still spent.
        self.assertEqual(self.value(f"select count(*) from account_trial_claims where shop_id='{MM_SHOP}'"), '2')
        self.sql(f"select create_account_shop('{MM_OWNERS[0]}','shop-new','New shop',null)")
        self.assertIn('trial_already_used',
                      self.sql(f"select start_account_trial('{MM_OWNERS[0]}','shop-new')", False).stderr)

    def test_ambiguous_ownership_aborts_before_creating_anything(self):
        self.apply([m for m in MIGRATIONS if m.stem not in ACCOUNT_MIGRATIONS])
        self.sql(LEGACY)
        self.sql("""insert into auth.users(id,email,raw_app_meta_data) values
                    ('44444444-4444-4444-4444-444444444444','a2@example.com',
                     '{"role":"owner","shop_id":"shop-a"}')""")
        failed, err = self.apply([m for m in MIGRATIONS if m.stem == '0094_account_premium'], check=False)
        self.assertIsNotNone(failed, 'two owner accounts on one shop must stop the cutover')
        self.assertIn('ambiguous ownership', err)
        # The refusal must leave nothing half-built behind.
        for table in ('shop_subscriptions', 'shop_devices', 'account_trial_claims'):
            self.assertEqual(self.value(f"select to_regclass('public.{table}') is null"), 't')
        self.assertEqual(self.value("select count(*) from pg_proc where proname='account_shop_role'"), '0')
        # Resolving the ambiguity is all it takes to retry the same push.
        self.sql("delete from auth.users where id='44444444-4444-4444-4444-444444444444'")
        self.apply([m for m in MIGRATIONS if m.stem == '0094_account_premium'])
        self.assertEqual(self.value('select count(*) from shop_subscriptions'), str(LEGACY_SHOPS))

    def test_more_devices_than_the_new_limit_aborts(self):
        self.apply([m for m in MIGRATIONS if m.stem not in ACCOUNT_MIGRATIONS])
        self.sql(LEGACY)
        self.sql("""insert into licenses(shop_id,key,plan,expires_at,activated_at,is_deleted,device_id,shop_name)
                    select 'shop-a','K-X'||n,'monthly','2026-11-01T00:00:00Z','2026-09-20T00:00:00Z',
                           false,'dev-x'||n,'Shop A' from generate_series(1,3) n""")
        failed, err = self.apply([m for m in MIGRATIONS if m.stem == '0094_account_premium'], check=False)
        self.assertIsNotNone(failed, 'a shop over the three-device limit must stop the cutover')
        self.assertIn('more than three devices', err)


if __name__ == '__main__':
    unittest.main()
