-- Apply after the existing migrations. No users or workshop records are deleted.
begin;

create table if not exists public.forage_security_events (
  id bigint generated always as identity primary key,
  occurred_at timestamptz not null default now(),
  actor_id uuid,
  event text not null,
  target text,
  details jsonb not null default '{}'
);
alter table public.forage_security_events enable row level security;
revoke all on public.forage_security_events from public, anon, authenticated;
grant select on public.forage_security_events to authenticated;
drop policy if exists admin_security_events on public.forage_security_events;
create policy admin_security_events on public.forage_security_events
  for select to authenticated using (public.is_admin());

create table if not exists public.forage_request_limits (
  actor_id uuid primary key, window_start timestamptz not null, attempts integer not null
);
alter table public.forage_request_limits enable row level security;
revoke all on public.forage_request_limits from public, anon, authenticated;

create or replace function public.consume_forage_admin_request(p_actor uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare n integer;
begin
  if p_actor is null then return false; end if;
  insert into public.forage_request_limits as r values (p_actor, now(), 1)
  on conflict (actor_id) do update set
    attempts = case when r.window_start < now() - interval '1 minute' then 1 else r.attempts + 1 end,
    window_start = case when r.window_start < now() - interval '1 minute' then now() else r.window_start end
  returning attempts into n;
  if n = 11 then
    insert into public.forage_security_events(actor_id,event) values(p_actor,'admin_rate_limit');
  end if;
  return n <= 10;
end;
$$;
revoke all on function public.consume_forage_admin_request(uuid) from public, anon, authenticated;
grant execute on function public.consume_forage_admin_request(uuid) to service_role;

-- A public signup must never become a usable workshop account. Only the
-- server's admin API can set app_metadata (user_metadata is untrusted).
create or replace function public.create_profile_for_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id,email,full_name,username,status)
  values(new.id,coalesce(new.email,''),left(coalesce(new.raw_user_meta_data->>'full_name','Utilisateur'),120),
    null, case when new.raw_app_meta_data->>'forage_managed' = 'true' then 'active' else 'dismissed' end)
  on conflict(id) do nothing;
  return new;
end;
$$;

create or replace function public.validate_forage_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
declare pages text[] := array['dashboard','products','stock','machines','team','validation','analytics'];
begin
  if length(new.full_name) not between 1 and 120 or new.full_name ~ '[<>[:cntrl:]]'
     or length(new.email) > 254
     or (new.username is not null and new.username !~ '^[a-zA-Z0-9._-]{3,32}$')
     or not (new.allowed_pages <@ pages) or not (new.writable_pages <@ new.allowed_pages)
     or array_position(new.allowed_pages,null) is not null
     or array_position(new.writable_pages,null) is not null
     or (new.role = 'visitor' and cardinality(new.writable_pages) > 0)
     or ((new.login_start_time is null) <> (new.login_end_time is null)) then
    raise exception 'Invalid profile fields' using errcode='22023';
  end if;
  -- Prevent two concurrent admins from demoting the last active administrator.
  perform pg_advisory_xact_lock(710170001);
  if tg_op = 'UPDATE' and old.role = 'admin' and old.status = 'active'
    and (new.role <> 'admin' or new.status <> 'active')
    and not exists(select 1 from public.profiles where id <> old.id and role='admin' and status='active') then
    raise exception 'The last active administrator is required';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists validate_forage_profile on public.profiles;
create trigger validate_forage_profile before insert or update on public.profiles
  for each row execute function public.validate_forage_profile();

-- Remove all policies on these application-owned tables: permissive policies
-- combine with OR, so leaving an older policy would silently bypass new rules.
do $$ declare p record; begin
  for p in select tablename,policyname from pg_policies where schemaname='public'
    and tablename in ('profiles','trusted_devices','device_access_requests','forage_device_sessions','workshop_snapshots') loop
    execute format('drop policy %I on public.%I',p.policyname,p.tablename);
  end loop;
end $$;
revoke all on public.profiles, public.trusted_devices, public.device_access_requests,
  public.forage_device_sessions, public.workshop_snapshots from public, anon, authenticated;
grant select on public.profiles, public.trusted_devices, public.device_access_requests,
  public.forage_device_sessions, public.workshop_snapshots to authenticated;
grant update(full_name,username,role,status,allowed_pages,writable_pages,can_export,login_start_time,login_end_time)
  on public.profiles to authenticated;
grant insert,update on public.workshop_snapshots to authenticated;
create policy profiles_read on public.profiles for select to authenticated
  using(id=auth.uid() or public.is_admin());
create policy profiles_admin_update on public.profiles for update to authenticated
  using(public.is_admin()) with check(public.is_admin());
-- Device IDs are bearer-like secrets: ordinary users do not need to enumerate them.
create policy devices_admin_read on public.trusted_devices for select to authenticated using(public.is_admin());
create policy requests_admin_read on public.device_access_requests for select to authenticated using(public.is_admin());
create policy sessions_admin_read on public.forage_device_sessions for select to authenticated using(public.is_admin());
create policy snapshot_read on public.workshop_snapshots for select to authenticated using(public.has_forage_app_access());
create policy snapshot_insert on public.workshop_snapshots for insert to authenticated
  with check(public.has_forage_app_access() and public.is_admin());
create policy snapshot_update on public.workshop_snapshots for update to authenticated
  using(public.has_forage_app_access() and public.is_staff())
  with check(public.has_forage_app_access() and public.is_staff());

create or replace function public.request_device_access(p_device_id text,p_device_label text,p_login_nonce text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare d public.trusted_devices%rowtype; r public.device_access_requests%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if coalesce(length(p_device_id),0) not between 20 and 128
    or coalesce(length(p_login_nonce),0) not between 10 and 128
    or coalesce(length(p_device_label),0) not between 1 and 160
    or p_device_id is distinct from public.current_forage_device_id()
    or p_login_nonce is distinct from public.current_forage_login_nonce() then
    raise exception 'Invalid device fields' using errcode='22023';
  end if;
  if not public.is_within_login_schedule(auth.uid()) then return jsonb_build_object('status','outside_schedule'); end if;
  if public.is_admin() then return jsonb_build_object('status','approved'); end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
  select * into d from public.trusted_devices where user_id=auth.uid() and device_id=p_device_id;
  if found then
    if d.access_status <> 'active' then return jsonb_build_object('status','rejected'); end if;
    return jsonb_build_object('status','approved');
  end if;
  select * into r from public.device_access_requests
    where user_id=auth.uid() and device_id=p_device_id and request_nonce=p_login_nonce
    order by requested_at desc limit 1;
  if found then return jsonb_build_object('status',case when r.status='approved' then 'pending' else r.status end); end if;
  if (select count(*) from public.device_access_requests where user_id=auth.uid()
      and requested_at > now()-interval '1 hour') >= 10 then
    if not exists(select 1 from public.forage_security_events where actor_id=auth.uid()
        and event='device_rate_limit' and occurred_at>now()-interval '1 hour') then
      insert into public.forage_security_events(actor_id,event) values(auth.uid(),'device_rate_limit');
    end if;
    return jsonb_build_object('status','rejected');
  end if;
  insert into public.device_access_requests(user_id,device_id,device_label,request_nonce,primary_on_approval)
    values(auth.uid(),p_device_id,p_device_label,p_login_nonce,
      not exists(select 1 from public.trusted_devices where user_id=auth.uid())) returning * into r;
  insert into public.forage_security_events(actor_id,event,target)
    values(auth.uid(),'device_requested',r.id::text);
  return jsonb_build_object('status','pending','request_id',r.id);
end;
$$;

-- Critical: recording a login must never grant device access.
create or replace function public.record_forage_device_login(p_label text,p_nonce text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not public.has_forage_app_access() then
    raise exception 'Approved device required' using errcode='42501';
  end if;
  if coalesce(length(p_label),0) not between 1 and 160
     or coalesce(length(p_nonce),0) not between 10 and 128
     or p_nonce is distinct from public.current_forage_login_nonce()
     or coalesce(length(public.current_forage_device_id()),0) not between 20 and 128 then
    raise exception 'Invalid login fields' using errcode='22023';
  end if;
  if public.is_admin() then
    insert into public.trusted_devices(user_id,device_id,device_label,is_primary,access_status,last_seen_at)
      values(auth.uid(),public.current_forage_device_id(),p_label,false,'active',now())
    on conflict(user_id,device_id) do update set device_label=excluded.device_label,last_seen_at=now();
  end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
  if not exists(select 1 from public.forage_device_sessions where user_id=auth.uid()
    and device_id=public.current_forage_device_id() and login_nonce=p_nonce) then
    insert into public.forage_device_sessions(user_id,device_id,device_label,login_nonce)
      values(auth.uid(),public.current_forage_device_id(),p_label,p_nonce);
    insert into public.forage_security_events(actor_id,event) values(auth.uid(),'device_login');
  end if;
end;
$$;

create or replace function public.audit_forage_change()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.forage_security_events(actor_id,event,target,details)
    values(auth.uid(),tg_table_name || ':' || lower(tg_op),new.id::text,
      case when tg_table_name='profiles' then jsonb_build_object('role',to_jsonb(new)->>'role','status',to_jsonb(new)->>'status')
           when tg_table_name='trusted_devices' then jsonb_build_object('status',to_jsonb(new)->>'access_status') else '{}'::jsonb end);
  return new;
end;
$$;
drop trigger if exists audit_profile on public.profiles;
create trigger audit_profile after insert or update on public.profiles for each row execute function public.audit_forage_change();
drop trigger if exists audit_device on public.trusted_devices;
create trigger audit_device after insert or update on public.trusted_devices for each row execute function public.audit_forage_change();
drop trigger if exists audit_device_request on public.device_access_requests;
create trigger audit_device_request after update on public.device_access_requests for each row execute function public.audit_forage_change();

-- Only named RPCs are exposed. Include every overload of these legacy names.
do $$ declare f record; begin
  for f in select p.oid::regprocedure as signature,p.proname from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
    and p.proname in ('is_admin','is_staff','create_profile_for_new_user','current_forage_device_id',
      'current_forage_login_nonce','is_within_login_schedule','has_forage_app_access','request_device_access',
      'decide_device_access_request','set_forage_device_status','record_forage_device_login',
      'record_forage_device_logout','list_forage_device_activity','validate_forage_profile','audit_forage_change') loop
    execute format('revoke all on function %s from public, anon, authenticated',f.signature);
    execute format('alter function %s set search_path = %L',f.signature,'');
    if f.proname not in ('create_profile_for_new_user','validate_forage_profile','audit_forage_change') then
      execute format('grant execute on function %s to authenticated',f.signature);
    end if;
  end loop;
end $$;
notify pgrst, 'reload schema';
commit;
