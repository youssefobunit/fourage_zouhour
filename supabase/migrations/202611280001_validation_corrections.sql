begin;

create or replace function public.can_correct_forage_drafts()
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and coalesce(public.has_forage_app_access(), false)
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and (
        p.role = 'admin' or (
          p.role = 'validation'
          and to_jsonb(p.allowed_pages) @> '["validation"]'::jsonb
          and to_jsonb(p.writable_pages) @> '["validation"]'::jsonb
        )
      )
    );
$$;

create or replace function public.forage_validation_kind(p_table text, p_row jsonb)
returns text language sql immutable set search_path = '' as $$
  select case p_table
    when 'sales' then case when p_row->>'draft' = '1' then 'sale' end
    when 'stock_additions' then case when p_row->>'draft' = '1' then
      case when p_row->>'return_purchase_id' is null then 'purchase' else 'supplier_return' end end
    when 'stock_transfers' then case when p_row->>'draft' = '1' then 'transfer' end
    when 'sale_returns' then case when p_row->>'status' = 'pending' then 'customer_return' end
    when 'operations' then case when p_row->>'completion_draft' = '1'
      and p_row->>'validated_at' is null and p_row->>'finished_at' is not null then
      case when p_row->>'external_production' = '1' then 'external_production' else 'production' end end
  end;
$$;

create or replace function public.forage_validation_draft_payload(p_table text, p_row jsonb)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'revision', md5(p_row::text),
    'photo_count', case when p_table in ('sales', 'stock_additions')
      then jsonb_array_length(coalesce((p_row->>'images')::jsonb, '[]'::jsonb)) else 0 end,
    'row', case when p_table in ('sales', 'stock_additions') and public.is_admin() is not true
      then p_row || '{"images":"[]"}'::jsonb else p_row end
  );
$$;

create or replace function public.get_forage_validation_draft(p_table text, p_id text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare draft jsonb;
begin
  if public.can_correct_forage_drafts() is not true then
    raise exception 'Validation write access required' using errcode = '42501';
  end if;
  if p_table is null or p_table not in ('sales','stock_additions','stock_transfers','sale_returns','operations') then
    raise exception 'Unknown validation type' using errcode = '22023';
  end if;
  select entry.value into draft
  from public.workshop_snapshots workshop,
    lateral jsonb_array_elements(workshop.snapshot->p_table) as entry(value)
  where workshop.id = 'main' and entry.value->>'id' = p_id;
  if draft is null then return null; end if;
  if public.forage_validation_kind(p_table, draft) is null then
    raise exception 'Draft is no longer pending' using errcode = '40001';
  end if;
  return public.forage_validation_draft_payload(p_table, draft);
end;
$$;

create or replace function public.forage_validation_display_value(p_snapshot jsonb, p_field text, p_value jsonb)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  lookup_table text;
  item jsonb;
  label text;
begin
  if p_value is null or p_value = 'null'::jsonb then return null; end if;
  lookup_table := case
    when p_field in ('product_id','output_product_id','scrap_product_id') then 'products'
    when p_field in ('depot_id','source_depot_id','destination_depot_id','output_depot_id',
      'remainder_depot_id','scrap_depot_id') then 'depots'
    when p_field = 'supplier_id' then 'suppliers'
    when p_field = 'client_id' then 'clients'
  end;
  if lookup_table is null then return p_value; end if;
  select entry.value into item from jsonb_array_elements(p_snapshot->lookup_table) entry(value)
  where entry.value->>'id' = p_value#>>'{}';
  label := concat_ws(' · ', nullif(item->>'name',''),
    nullif(case when lookup_table = 'products' then item->>'reference' else item->>'company' end,''));
  return coalesce(to_jsonb(nullif(label,'')), p_value);
end;
$$;

create or replace function public.edit_forage_validation_draft(
  p_table text, p_id text, p_revision text, p_changes jsonb,
  p_removed_photos integer[], p_added_photos text[]
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  workshop jsonb;
  prior jsonb;
  corrected jsonb;
  draft_position bigint;
  kind text;
  allowed text[];
  photos jsonb;
  next_photos jsonb;
  photo_count integer;
  changes jsonb := '{}'::jsonb;
  field text;
  actor_name text;
  original_quantity bigint;
  other_returns bigint;
  return_id text;
begin
  if public.can_correct_forage_drafts() is not true then
    raise exception 'Validation write access required' using errcode = '42501';
  end if;
  if p_table is null or p_table not in ('sales','stock_additions','stock_transfers','sale_returns','operations')
    or jsonb_typeof(p_changes) is distinct from 'object' then
    raise exception 'Invalid validation correction' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(710170002);
  select snapshot into workshop from public.workshop_snapshots where id = 'main' for update;
  select value, position into prior, draft_position
  from jsonb_array_elements(workshop->p_table) with ordinality as entry(value, position)
  where value->>'id' = p_id;
  kind := public.forage_validation_kind(p_table, prior);
  if kind is null or md5(prior::text) is distinct from p_revision then
    raise exception 'Draft changed' using errcode = '40001';
  end if;

  allowed := case kind
    when 'sale' then array['product_id','depot_id','client_id','pieces','quantity','unit','transport_charge']
    when 'purchase' then array['product_id','depot_id','supplier_id','pieces','quantity','unit','transport_charge','receipt_number']
    when 'supplier_return' then array['pieces','quantity','unit','receipt_number']
    when 'customer_return' then array['pieces']
    when 'transfer' then array['product_id','source_depot_id','destination_depot_id','pieces']
    else array['output_pieces','output_depot_id','remainder_pieces','remainder_depot_id',
      'scrap_pieces','scrap_depot_id','scrap_product_id','final_image','remainder_image','scrap_image']
  end;
  if exists (select 1 from jsonb_object_keys(p_changes) as keys(key) where not (key = any(allowed))) then
    raise exception 'Field cannot be corrected' using errcode = '42501';
  end if;
  corrected := prior || p_changes;

  if kind in ('purchase','sale') then
    if coalesce((corrected->>'pieces')::bigint, 0) <= 0 or coalesce((corrected->>'quantity')::numeric, 0) <= 0 then
      raise exception 'Positive transaction quantity required' using errcode = '22023';
    end if;
  elsif kind = 'supplier_return' then
    return_id := prior->>'return_purchase_id';
    select (entry->>'pieces')::bigint into original_quantity
    from jsonb_array_elements(workshop->'stock_additions') entry
    where entry->>'id' = return_id and entry->>'draft' = '0' and entry->>'return_purchase_id' is null;
    select coalesce(sum(abs((entry->>'pieces')::bigint)), 0) into other_returns
    from jsonb_array_elements(workshop->'stock_additions') entry
    where entry->>'return_purchase_id' = return_id and entry->>'id' <> p_id;
    if original_quantity is null or coalesce((corrected->>'pieces')::bigint, 0) >= 0
      or other_returns - (corrected->>'pieces')::bigint > original_quantity then
      raise exception 'Supplier return exceeds original purchase' using errcode = '22023';
    end if;
  elsif kind = 'customer_return' then
    return_id := prior->>'sale_id';
    select (entry->>'pieces')::bigint into original_quantity
    from jsonb_array_elements(workshop->'sales') entry where entry->>'id' = return_id and entry->>'draft' = '0';
    select coalesce(sum((entry->>'pieces')::bigint), 0) into other_returns
    from jsonb_array_elements(workshop->'sale_returns') entry
    where entry->>'sale_id' = return_id and entry->>'status' <> 'rejected' and entry->>'id' <> p_id;
    if original_quantity is null or coalesce((corrected->>'pieces')::bigint, 0) <= 0
      or other_returns + (corrected->>'pieces')::bigint > original_quantity then
      raise exception 'Customer return exceeds original sale' using errcode = '22023';
    end if;
  end if;

  foreach field in array array['product_id','client_id','supplier_id','depot_id','source_depot_id',
    'destination_depot_id','output_depot_id','remainder_depot_id','scrap_depot_id','scrap_product_id'] loop
    if p_changes ? field and corrected->>field is not null and not exists (
      select 1 from jsonb_array_elements(workshop->(case field
        when 'product_id' then 'products' when 'scrap_product_id' then 'products'
        when 'client_id' then 'clients' when 'supplier_id' then 'suppliers' else 'depots' end)) value
      where value->>'id' = corrected->>field
    ) then
      raise exception 'Unknown referenced record' using errcode = '22023';
    end if;
  end loop;

  if coalesce(cardinality(p_removed_photos),0) + coalesce(cardinality(p_added_photos),0) > 0 then
    if kind not in ('sale','purchase') then
      raise exception 'This record has no transaction photos' using errcode = '22023';
    end if;
    photos := coalesce((prior->>'images')::jsonb, '[]'::jsonb);
    photo_count := jsonb_array_length(photos);
    if exists (select 1 from unnest(p_removed_photos) as removed(idx) where idx is null or idx < 0 or idx >= photo_count)
      or cardinality(p_removed_photos) <> (select count(distinct idx) from unnest(p_removed_photos) removed(idx))
      or coalesce(cardinality(p_added_photos),0) > 10 then
      raise exception 'Invalid photo selection' using errcode = '22023';
    end if;
    select coalesce(jsonb_agg(value order by position), '[]'::jsonb)
    into next_photos from jsonb_array_elements(photos) with ordinality as entry(value,position)
    where not (position - 1 = any(coalesce(p_removed_photos, '{}'::integer[])));
    next_photos := next_photos || coalesce(to_jsonb(p_added_photos), '[]'::jsonb);
    if jsonb_array_length(next_photos) > 10 or (photo_count > 0 and next_photos = '[]'::jsonb) then
      raise exception 'Invalid number of photos' using errcode = '22023';
    end if;
    if next_photos <> photos then
      corrected := corrected || jsonb_build_object('images', next_photos::text);
      changes := jsonb_build_object('images', jsonb_build_object(
        'before', photo_count, 'after', jsonb_array_length(next_photos),
        'removed', (select coalesce(jsonb_agg(idx + 1 order by idx),'[]'::jsonb)
          from unnest(p_removed_photos) as removed(idx)),
        'added', coalesce(cardinality(p_added_photos), 0)
      ));
    end if;
  end if;

  for field in select jsonb_object_keys(p_changes) loop
    if corrected->field is distinct from prior->field then
      if field in ('final_image','remainder_image','scrap_image') then
        changes := changes || jsonb_build_object(field, jsonb_build_object(
          'before', case when prior->>field is not null then 'Photo' end,
          'after', case when corrected->>field is not null then 'Photo modifiée' end));
      else
        changes := changes || jsonb_build_object(field, jsonb_build_object(
          'before', public.forage_validation_display_value(workshop, field, prior->field),
          'after', public.forage_validation_display_value(workshop, field, corrected->field)));
      end if;
    end if;
  end loop;
  if changes = '{}'::jsonb then return public.forage_validation_draft_payload(p_table, prior); end if;

  update public.workshop_snapshots
  set snapshot = jsonb_set(workshop, array[p_table, (draft_position - 1)::text], corrected)
  where id = 'main';
  select coalesce(nullif(full_name,''), username, id::text) into actor_name
  from public.profiles where id = auth.uid();
  insert into public.forage_security_events(actor_id,event,target,details)
  values (auth.uid(),'validation_edit',p_id,jsonb_build_object(
    'kind',kind,'table',p_table,'actor_name',actor_name,
    'record',public.forage_validation_display_value(workshop,'product_id',corrected->'product_id'),
    'changes',changes
  ));
  return public.forage_validation_draft_payload(p_table, corrected);
end;
$$;

revoke all on function public.can_correct_forage_drafts(), public.forage_validation_kind(text,jsonb),
  public.forage_validation_draft_payload(text,jsonb), public.forage_validation_display_value(jsonb,text,jsonb),
  public.get_forage_validation_draft(text,text), public.edit_forage_validation_draft(text,text,text,jsonb,integer[],text[])
  from public, anon, authenticated;
grant execute on function public.get_forage_validation_draft(text,text),
  public.edit_forage_validation_draft(text,text,text,jsonb,integer[],text[]) to authenticated;

create or replace function public.save_forage_workshop(p_snapshot jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  previous jsonb;
  payload jsonb := p_snapshot;
  administrator boolean;
  transaction_table text;
  restored_rows jsonb;
  corrected_fields jsonb;
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
      -- Existing photos, including deletions, are authoritative on the server.
      -- Only the draft correction RPC may alter them after initial insertion.
      select coalesce(jsonb_agg(
        case when prior.value ? 'images'
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

    -- Full snapshots from another device may predate a correction. Keep the
    -- fields changed through the correction RPC while the record is pending.
    foreach transaction_table in array array['stock_additions','sales','stock_transfers','sale_returns','operations'] loop
      select jsonb_object_agg(record_id, fields) into corrected_fields
      from (
        select event.target as record_id, jsonb_agg(distinct field) as fields
        from public.forage_security_events event
        cross join lateral jsonb_object_keys(event.details->'changes') field
        where event.event = 'validation_edit' and event.details->>'table' = transaction_table
          and field <> 'images'
        group by event.target
      ) corrected;
      if corrected_fields is null then continue; end if;
      select coalesce(jsonb_agg(
        incoming.value || coalesce((
          select jsonb_object_agg(field, prior.value->field)
          from jsonb_array_elements_text(corrected_fields->(incoming.value->>'id')) field
          where prior.value ? field
        ), '{}'::jsonb) order by incoming.position
      ), '[]'::jsonb)
      into restored_rows
      from jsonb_array_elements(payload->transaction_table) with ordinality as incoming(value,position)
      left join jsonb_array_elements(previous->transaction_table) prior(value)
        on prior.value->>'id' = incoming.value->>'id'
        and public.forage_validation_kind(transaction_table, prior.value) is not null;
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

notify pgrst, 'reload schema';
commit;
