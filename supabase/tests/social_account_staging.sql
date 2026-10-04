-- Run only on staging AFTER migrations 0094–0096. All fixtures roll back.
-- Auth provider verification still needs native Google/Apple staging testing.
begin;
do $$
declare owner_id uuid:=gen_random_uuid(); staff_id uuid:=gen_random_uuid();
  first_shop jsonb; second_shop jsonb; proof text:=md5(gen_random_uuid()::text)||md5(gen_random_uuid()::text);
begin
  if has_function_privilege('anon','create_social_account_shop(uuid,text)','EXECUTE')
    or has_function_privilege('authenticated','create_social_account_shop(uuid,text)','EXECUTE')
    or has_function_privilege('authenticated','consume_social_reauth_proof(uuid,text,timestamptz)','EXECUTE') then
    raise exception 'social RPC exposed to application roles';
  end if;
  insert into auth.users(id,email,is_anonymous,raw_app_meta_data)
    values(owner_id,owner_id::text||'@social-test.invalid',false,'{}');
  if resolve_social_account(owner_id)->>'needs_shop_name' is distinct from 'true' then
    raise exception 'first-account preparation failed';
  end if;
  first_shop:=create_social_account_shop(owner_id,'Staging rollback test');
  second_shop:=create_social_account_shop(owner_id,'Retry');
  if first_shop->>'shop_id' is distinct from second_shop->>'shop_id'
    or first_shop->>'plan' is distinct from 'free'
    or exists(select 1 from account_trial_claims where owner_user_id=owner_id)
    or exists(select 1 from shop_devices where user_id=owner_id) then
    raise exception 'first-shop signup changed trial/device/idempotency authority';
  end if;
  insert into auth.users(id,email,is_anonymous,raw_app_meta_data)
    values(staff_id,staff_id::text||'@social-test.invalid',false,
      jsonb_build_object('role','staff','shop_id',first_shop->>'shop_id'));
  if resolve_social_account(staff_id)->>'role' is distinct from 'staff' then
    raise exception 'staff role not preserved';
  end if;
  begin
    perform create_social_account_shop(staff_id,'Forbidden');
    raise exception 'staff unexpectedly became owner';
  exception when others then
    if sqlerrm<>'forbidden' then raise; end if;
  end;
  update shop_subscriptions set is_archived=true where shop_id=first_shop->>'shop_id';
  begin
    perform create_social_account_shop(owner_id,'Forbidden');
    raise exception 'archived owner unexpectedly created shop';
  exception when others then
    if sqlerrm<>'shop_archived' then raise; end if;
  end;
  if not consume_social_reauth_proof(owner_id,proof,now()+interval '5 minutes')
    or consume_social_reauth_proof(owner_id,proof,now()+interval '5 minutes') then
    raise exception 'social proof replay accepted';
  end if;
end $$;
rollback;
