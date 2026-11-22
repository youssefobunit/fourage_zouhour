-- The sole destructive-maintenance account. Change this email only by changing
-- this migration policy deliberately, never from a client application.
begin;

create or replace function public.is_forage_owner()
returns boolean language sql stable security definer set search_path='' as $$
  select exists (
    select 1 from public.profiles
    where id=auth.uid() and lower(email)='owner@younes.com'
      and role='admin' and status='active'
  );
$$;
revoke all on function public.is_forage_owner() from public,anon,authenticated;
grant execute on function public.is_forage_owner() to authenticated;

-- Give the designated existing account its full administrator profile. This is
-- idempotent and does nothing if that email has not been created yet.
update public.profiles set
  role='admin', status='active',
  allowed_pages=array['dashboard','products','stock','machines','team','validation','analytics'],
  writable_pages=array['dashboard','products','stock','machines','team','validation','analytics'],
  can_export=true
where lower(email)='owner@younes.com';

-- Other administrators can manage the workshop but cannot delete history or
-- inventory through a forged full-snapshot upload. Operator/validator draft
-- flows remain governed by the prior validation trigger.
create or replace function public.guard_forage_owner_maintenance()
returns trigger language plpgsql security definer set search_path='' as $$
declare t text; old_row jsonb;
begin
  if not public.is_admin() or public.is_forage_owner() then return new; end if;
  foreach t in array array['products','categories','machines','operations','stock_additions','suppliers','clients','sales','competitors','transaction_payments','stock_transfers','sale_returns','operator_payments','depots'] loop
    for old_row in select value from jsonb_array_elements(coalesce(old.snapshot->t,'[]'::jsonb)) loop
      if not exists (
        select 1 from jsonb_array_elements(coalesce(new.snapshot->t,'[]'::jsonb)) current_row
        where current_row->>'id'=old_row->>'id'
      ) then
        raise exception 'Only owner@younes.com may permanently delete workshop records' using errcode='42501';
      end if;
    end loop;
  end loop;
  return new;
end;
$$;
revoke all on function public.guard_forage_owner_maintenance() from public,anon,authenticated;
drop trigger if exists guard_forage_owner_maintenance on public.workshop_snapshots;
create trigger guard_forage_owner_maintenance before update on public.workshop_snapshots
  for each row execute function public.guard_forage_owner_maintenance();

notify pgrst, 'reload schema';
commit;
