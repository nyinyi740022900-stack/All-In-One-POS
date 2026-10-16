"""Migration 0104 — which product photos may be swept, and the usage report.

Against disposable PostgreSQL only. The property that matters is the safe
direction: any photo something might still use is kept. A wrong keep costs a
few KB; a wrong delete is a customer's missing product photo.
"""
import json, pathlib, shutil, subprocess, tempfile, unittest

MIGRATION = pathlib.Path(__file__).resolve().parents[1] / 'migrations/0104_storage_usage_and_photo_sweep.sql'
URL = 'https://ref.supabase.co/storage/v1/object/public/product-images/'


class StorageSweep(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix='storage-sweep-', dir='/tmp')
        cls.port = '55497'
        subprocess.run(['initdb', '-D', cls.tmp + '/db', '-A', 'trust', '--no-locale'],
                       check=True, stdout=subprocess.DEVNULL)
        subprocess.run(['pg_ctl', '-D', cls.tmp + '/db', '-l', cls.tmp + '/server.log',
                        '-o', f'-k {cls.tmp} -p {cls.port} -h ""', '-w', 'start'],
                       check=True, stdout=subprocess.DEVNULL)

    @classmethod
    def tearDownClass(cls):
        subprocess.run(['pg_ctl', '-D', cls.tmp + '/db', '-m', 'immediate', 'stop'],
                       stdout=subprocess.DEVNULL)
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def sql(self, text, check=True):
        p = subprocess.run(['psql', '-h', self.tmp, '-p', self.port, '-d', 'postgres',
                            '-XAt', '-v', 'ON_ERROR_STOP=1'],
                           input=text, text=True, capture_output=True)
        if check and p.returncode:
            self.fail(p.stderr)
        return p

    def setUp(self):
        self.assertTrue(MIGRATION.exists(), '0104 must exist')
        self.sql("""
          drop schema if exists public cascade; create schema public;
          drop schema if exists storage cascade; create schema storage;
          do $$ begin create role authenticated; exception when duplicate_object then null; end $$;
          do $$ begin create role anon; exception when duplicate_object then null; end $$;
          do $$ begin create role service_role bypassrls; exception when duplicate_object then null; end $$;
          grant usage on schema public, storage to authenticated, anon, service_role;
          create table storage.objects(id uuid default gen_random_uuid(), bucket_id text, name text,
                                       metadata jsonb, created_at timestamptz default now());
          create table products(id text primary key, shop_id text not null, name text,
                                image_url text, image_path text, is_deleted boolean default false);
          create table storefronts(shop_id text primary key, logo_url text);
          create table sales(id text primary key, shop_id text not null, total int);
        """)
        self.sql(MIGRATION.read_text())

    def photo(self, name, days_old=60, size=1000, bucket='product-images'):
        self.sql(f"""insert into storage.objects(bucket_id,name,metadata,created_at)
                     values('{bucket}','{name}','{{"size":{size}}}',now()-interval '{days_old} days')""")

    def orphans(self, min_age="interval '30 days'"):
        out = self.sql(f"select name from orphan_product_images({min_age}) order by name").stdout
        return out.split()

    def test_a_replaced_photo_goes_and_the_current_one_stays(self):
        self.photo('a/p-old.jpg')
        self.photo('a/p-new.jpg')
        self.sql(f"insert into products(id,shop_id,image_url) values('p1','a','{URL}a/p-new.jpg')")
        self.assertEqual(self.orphans(), ['a/p-old.jpg'])

    def test_receipt_logos_are_never_swept(self):
        # Their URLs live only in each device's settings — the server can't see use.
        self.photo('a/shop-logo-1.png')
        self.photo('shop-logo-2.jpeg')
        self.assertEqual(self.orphans(), [])

    def test_young_files_are_kept_and_the_floor_cannot_be_lowered(self):
        self.photo('a/p-fresh.jpg', days_old=3)
        self.photo('a/p-week.jpg', days_old=10)
        self.assertEqual(self.orphans(), [])
        self.assertEqual(self.orphans("interval '0 days'"), ['a/p-week.jpg'],
                         'a 0-day request is floored at 7 days, never sweeping a 3-day-old upload')

    def test_any_reference_in_any_shop_keeps_a_file(self):
        self.photo('a/p-deleted-product.jpg')
        self.photo('a/p-by-path.jpg')
        self.photo('b/logo-1.jpg')
        self.photo('root-p.jpg')
        self.photo('c/p-query.jpg')
        self.sql(f"""
          insert into products(id,shop_id,image_url,is_deleted) values('p1','a','{URL}a/p-deleted-product.jpg',true);
          insert into products(id,shop_id,image_path) values('p2','a','a/p-by-path.jpg');
          insert into storefronts(shop_id,logo_url) values('b','{URL}b/logo-1.jpg');
          insert into products(id,shop_id,image_url) values('p3','z','{URL}root-p.jpg');
          insert into products(id,shop_id,image_url) values('p4','c','{URL}c/p-query.jpg?t=1#x');
        """)
        self.assertEqual(self.orphans(), [])

    def test_a_similar_name_is_not_a_reference(self):
        self.photo('a/p-1.jpg')
        self.sql(f"insert into products(id,shop_id,image_url) values('p1','a','{URL}a/xp-1.jpg')")
        self.assertEqual(self.orphans(), ['a/p-1.jpg'])

    def test_other_buckets_are_untouched(self):
        self.photo('a/proof.png', bucket='payment-proofs')
        self.assertEqual(self.orphans(), [])

    def test_no_client_role_can_list_or_report(self):
        for fn in ['orphan_product_images()', 'admin_storage_report()']:
            for role in ['authenticated', 'anon']:
                p = self.sql(f'set role {role}; select {fn}', False)
                self.assertNotEqual(p.returncode, 0, f'{role} ran {fn}')

    def test_usage_report_attributes_rows_and_photos_per_shop(self):
        self.sql("""
          insert into sales values('s1','a',1),('s2','a',2),('s3','b',3);
          insert into products(id,shop_id) values('p1','a');
        """)
        self.photo('a/p-1.jpg', size=500)
        self.photo('a/p-2.jpg', size=700)
        self.photo('legacy-root.jpg', size=300)
        report = json.loads(self.sql('select admin_storage_report()').stdout)
        shops = {s['shop_id']: s for s in report['shops']}
        self.assertEqual(shops['a']['rows'], 3)
        self.assertEqual(shops['b']['rows'], 1)
        self.assertEqual(shops['a']['photos'], 2)
        self.assertEqual(shops['a']['photo_bytes'], 1200)
        self.assertGreater(shops['a']['bytes'], shops['b']['bytes'])
        self.assertEqual(report['unfoldered_photos'], 1)
        self.assertEqual(report['unfoldered_photo_bytes'], 300)
        self.assertGreater(report['database_bytes'], 0)
        self.assertEqual(report['shops'][0]['shop_id'], 'a', 'largest first')

    def test_a_table_added_later_is_counted_without_editing_the_report(self):
        self.sql("create table new_feature(id text, shop_id text); insert into new_feature values('x','b')")
        report = json.loads(self.sql('select admin_storage_report()').stdout)
        self.assertEqual({s['shop_id']: s['rows'] for s in report['shops']}, {'b': 1})


if __name__ == '__main__':
    unittest.main()
