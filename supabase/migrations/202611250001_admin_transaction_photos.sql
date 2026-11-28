begin;

-- SQLite stores image arrays as JSON text, so keep that representation in the
-- shared snapshot. Older clients can still load the redacted transactions.
create or replace function public.get_forage_workshop(
  p_include_families boolean, p_include_catalog_families boolean
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  result jsonb;
  transaction_table text;
  redacted_rows jsonb;
begin
  if auth.uid() is null or public.has_forage_app_access() is not true then
    raise exception 'Approved device required' using errcode = '42501';
  end if;

  select snapshot into result from public.workshop_snapshots where id = 'main';
  if result is null then return null; end if;

  if public.is_admin() is not true then
    result := result || '{"operator_payments":[],"transaction_payments":[]}'::jsonb;
    foreach transaction_table in array array['stock_additions', 'sales'] loop
      select coalesce(jsonb_agg(entry.row || '{"images":"[]"}'::jsonb order by entry.position), '[]'::jsonb)
      into redacted_rows
      from jsonb_array_elements(result->transaction_table) with ordinality as entry(row, position);
      result := jsonb_set(result, array[transaction_table], redacted_rows);
    end loop;
  end if;

  if not coalesce(p_include_families, false) then
    result := jsonb_set(result, '{categories}', (
      select coalesce(jsonb_agg(value - 'families' order by position), '[]'::jsonb)
      from jsonb_array_elements(result->'categories') with ordinality as entries(value, position)
    ));
  end if;
  if coalesce(p_include_catalog_families, false) then
    if not (result ? 'catalog_families') then
      result := result || '{"catalog_families":[]}'::jsonb;
    end if;
  else
    result := result - 'catalog_families';
  end if;
  return result;
end;
$$;

create or replace function public.save_forage_workshop(p_snapshot jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  previous jsonb;
  payload jsonb := p_snapshot;
  administrator boolean;
  transaction_table text;
  restored_rows jsonb;
begin
  if auth.uid() is null or public.has_forage_app_access() is not true or public.is_staff() is not true then
    raise exception 'Write permission required' using errcode = '42501';
  end if;
  if jsonb_typeof(payload) is distinct from 'object' then
    raise exception 'Invalid snapshot' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(710170002);
  select snapshot into previous from public.workshop_snapshots where id = 'main' for update;
  administrator := coalesce(public.is_admin(), false);
  if not administrator then
    if previous is null then
      raise exception 'Administrator must initialize workshop' using errcode = '42501';
    end if;
    if payload->'operator_payments' is distinct from '[]'::jsonb
       or payload->'transaction_payments' is distinct from '[]'::jsonb then
      raise exception 'Private financial data denied' using errcode = '42501';
    end if;
    payload := payload || jsonb_build_object(
      'operator_payments', previous->'operator_payments',
      'transaction_payments', previous->'transaction_payments'
    );
  end if;

  if previous is not null then
    foreach transaction_table in array array['stock_additions', 'sales'] loop
      if jsonb_typeof(payload->transaction_table) is distinct from 'array' then
        raise exception 'Invalid transaction list' using errcode = '22023';
      end if;
      -- Staff may attach photos when creating a transaction. Saving a record
      -- from a redacted mirror must keep its existing photos intact.
      select coalesce(jsonb_agg(
        case when prior.value ? 'images'
          and (not administrator or coalesce(incoming.value->>'images', '[]') = '[]')
          then incoming.value || jsonb_build_object('images', prior.value->'images')
          else incoming.value end
        order by incoming.position
      ), '[]'::jsonb)
      into restored_rows
      from jsonb_array_elements(payload->transaction_table) with ordinality as incoming(value, position)
      left join jsonb_array_elements(previous->transaction_table) as prior(value)
        on prior.value->>'id' = incoming.value->>'id';
      payload := jsonb_set(payload, array[transaction_table], restored_rows);
    end loop;
  end if;

  if previous is null then
    insert into public.workshop_snapshots(id, snapshot) values ('main', payload);
  else
    update public.workshop_snapshots set snapshot = payload where id = 'main';
  end if;
end;
$$;

create or replace function public.get_forage_transaction_photos(p_sale boolean, p_id text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare images jsonb;
begin
  if auth.uid() is null or public.has_forage_app_access() is not true or public.is_admin() is not true then
    raise exception 'Administrator permission required' using errcode = '42501';
  end if;
  select (entry.value->>'images')::jsonb into images
  from public.workshop_snapshots workshop
  cross join lateral jsonb_array_elements(
    workshop.snapshot->(case when p_sale then 'sales' else 'stock_additions' end)
  ) as entry(value)
  where workshop.id = 'main' and entry.value->>'id' = p_id;
  return coalesce(images, '[]'::jsonb);
end;
$$;

revoke all on function public.get_forage_workshop(boolean, boolean), public.save_forage_workshop(jsonb),
  public.get_forage_transaction_photos(boolean, text) from public, anon, authenticated;
grant execute on function public.get_forage_workshop(boolean, boolean), public.save_forage_workshop(jsonb),
  public.get_forage_transaction_photos(boolean, text) to authenticated;
notify pgrst, 'reload schema';
commit;
