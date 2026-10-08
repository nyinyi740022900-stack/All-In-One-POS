"""Holds supabase/rollback/0094_0096_rollback.sql to actually reaching 0093.

A rollback script nobody has run is a wish, not a plan. This builds two
disposable databases — one stopped at 0093, one carried to 0098 and then rolled
back — and fails unless their schemas match down to column types, function
signatures and policy definitions. That last one matters: 0094 narrowed
org_branches_owner from `for all` to `for select`, which a name-only comparison
would miss.

It also checks the rollback keeps the data 0093 owns (a rollback that drops the
shops it was protecting is worse than no rollback).
"""
import pathlib, shutil, subprocess, tempfile, unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
MIGRATIONS = sorted((ROOT / 'supabase/migrations').glob('[0-9]*.sql'))
ACCOUNT = ('0094_account_premium', '0095_account_billing', '0096_social_accounts',
           '0097_gateway_checkout_guard', '0098_mmpay_checkouts',
           '0099_reclaim_expired_checkouts')
ROLLBACK = ROOT / 'supabase/rollback/0094_0096_rollback.sql'

from supabase.tests.migration_chain_test import PLATFORM, LEGACY, LEGACY_SHOPS

# Everything that makes up "the schema" for comparison purposes.
SNAPSHOTS = {
    'tables': """select coalesce(string_agg(tablename, E'\\n' order by tablename), '')
                 from pg_tables where schemaname = 'public'""",
    'columns': """select coalesce(string_agg(table_name || '.' || column_name || ' ' || data_type
                                             || coalesce(' default ' || column_default, ''),
                                             E'\\n' order by table_name, column_name), '')
                  from information_schema.columns where table_schema = 'public'""",
    'functions': """select coalesce(string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
                                               E'\\n' order by 1), '')
                    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'public'""",
    # Name, command, roles and both expressions: a narrowed policy must show up.
    'policies': """select coalesce(string_agg(c.relname || ':' || p.polname || ' ' || p.polcmd
                                              || ' roles=' || coalesce(array_to_string(array(
                                                   select rolname from pg_roles where oid = any(p.polroles)
                                                   order by rolname), ','), 'public')
                                              || ' using=' || coalesce(pg_get_expr(p.polqual, p.polrelid), '-')
                                              || ' check=' || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '-'),
                                              E'\\n' order by 1), '')
                   from pg_policy p join pg_class c on c.oid = p.polrelid""",
    'rls': """select coalesce(string_agg(relname || '=' || relrowsecurity::text, E'\\n' order by relname), '')
              from pg_class c join pg_namespace n on n.oid = c.relnamespace
              where n.nspname = 'public' and c.relkind = 'r'""",
    'indexes': """select coalesce(string_agg(indexdef, E'\\n' order by indexdef), '')
                  from pg_indexes where schemaname = 'public'""",
}


class Cluster:
    """A disposable PostgreSQL instance in /tmp (the socket path is capped at 103 bytes)."""

    def __init__(self, port):
        self.port = str(port)
        self.dir = tempfile.mkdtemp(prefix='rollback-', dir='/tmp')
        subprocess.run(['initdb', '-D', self.dir + '/db', '-A', 'trust', '--no-locale'],
                       check=True, stdout=subprocess.DEVNULL)
        subprocess.run(['pg_ctl', '-D', self.dir + '/db', '-l', self.dir + '/server.log',
                        '-o', f'-k {self.dir} -p {self.port} -h ""', '-w', 'start'],
                       check=True, stdout=subprocess.DEVNULL)

    def stop(self):
        subprocess.run(['pg_ctl', '-D', self.dir + '/db', '-m', 'immediate', 'stop'],
                       stdout=subprocess.DEVNULL)
        shutil.rmtree(self.dir, ignore_errors=True)

    def _psql(self, args, **kw):
        return subprocess.run(['psql', '-h', self.dir, '-p', self.port, '-d', 'postgres',
                               '-XAt', '-v', 'ON_ERROR_STOP=1'] + args,
                              text=True, capture_output=True, **kw)

    def sql(self, text):
        return self._psql([], input=text)

    def file(self, path):
        # cwd matters: the rollback script pulls in migrations with \ir.
        return self._psql(['-f', str(path)], cwd=str(path.parent))

    def value(self, query):
        return self.sql(query).stdout.strip()

    def snapshot(self):
        return {name: self.value(query) for name, query in SNAPSHOTS.items()}


class Rollback(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.reference = Cluster(55495)   # stops at 0093
        cls.rolled_back = Cluster(55496)  # 0098, then rolled back
        for db in (cls.reference, cls.rolled_back):
            assert not db.sql(PLATFORM).returncode, 'platform bootstrap failed'
        for path in MIGRATIONS:
            if path.stem not in ACCOUNT:
                for db in (cls.reference, cls.rolled_back):
                    p = db.file(path)
                    assert not p.returncode, f'{path.name}: {p.stderr}'
        for db in (cls.reference, cls.rolled_back):
            assert not db.sql(LEGACY).returncode, 'legacy seed failed'
        for path in MIGRATIONS:
            if path.stem in ACCOUNT:
                p = cls.rolled_back.file(path)
                assert not p.returncode, f'{path.name}: {p.stderr}'
        cls.rollback_result = cls.rolled_back.file(ROLLBACK)
        # Captured here, not in the tests: one test reapplies the cutover, and
        # unittest's alphabetical order would otherwise let it mutate the
        # database another test is still inspecting.
        cls.reference_schema = cls.reference.snapshot()
        cls.rolled_back_schema = cls.rolled_back.snapshot()
        cls.counts = {
            name: (cls.reference.value(query), cls.rolled_back.value(query))
            for name, query in (
                ('shops', 'select count(distinct shop_id) from licenses'),
                ('licences', 'select count(*) from licenses'),
                ('users', 'select count(*) from auth.users'),
                ('branches', 'select count(*) from org_branches'),
            )
        }

    @classmethod
    def tearDownClass(cls):
        cls.reference.stop()
        cls.rolled_back.stop()

    def test_rollback_script_runs(self):
        self.assertEqual(self.rollback_result.returncode, 0, self.rollback_result.stderr)

    def test_rollback_reproduces_the_0093_schema(self):
        reference, rolled_back = self.reference_schema, self.rolled_back_schema
        for part in SNAPSHOTS:
            with self.subTest(part):
                missing = set(reference[part].splitlines()) - set(rolled_back[part].splitlines())
                extra = set(rolled_back[part].splitlines()) - set(reference[part].splitlines())
                self.assertEqual(
                    (sorted(missing), sorted(extra)), ([], []),
                    f'{part} differs after rollback — missing from the rolled-back database: '
                    f'{sorted(missing)}; left over from the cutover: {sorted(extra)}')

    def test_rollback_keeps_the_shops_it_was_protecting(self):
        self.assertEqual(self.counts['shops'][1], str(LEGACY_SHOPS))
        for name, (reference, rolled_back) in self.counts.items():
            with self.subTest(name):
                self.assertEqual(rolled_back, reference, f'{name} changed across the rollback')

    def test_cutover_can_be_reapplied_after_a_rollback(self):
        for path in MIGRATIONS:
            if path.stem in ACCOUNT:
                p = self.rolled_back.file(path)
                self.assertEqual(p.returncode, 0, f'{path.name} after rollback: {p.stderr}')
        self.assertEqual(self.rolled_back.value('select count(*) from shop_subscriptions'),
                         str(LEGACY_SHOPS))


if __name__ == '__main__':
    unittest.main()
