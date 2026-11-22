begin;

-- Keep the existing trigger and its authorization checks while extending
-- the catalog data accepted by its validator.
create or replace function public.validate_workshop_snapshot()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  tables text[] := array['products','categories','catalog_families','machines','operations','stock_additions','suppliers','clients','sales','competitors','transaction_payments','stock_transfers','sale_returns','operator_payments','depots'];
  t text; k text; row_new jsonb; row_old jsonb; before_rows jsonb; changed record; field record;
  allowed text[]; required text[]; list_item jsonb;
  numeric_fields text[] := array['width','length_meters','thickness','diameter','meters_per_piece','quantity','amount'];
  integer_fields text[] := array['pieces','initial_stock','copies','machine_unit_number','hopper_pieces','output_pieces','scrap_pieces','remainder_pieces','planned_pieces','temporary_input_pieces','started_at','finished_at','validated_at','created_at','paid_at','deadline','return_purchase_id','stock_addition_id'];
  flags text[] := array['manufactured','diameter_is_external','diameter_calculated_from_dimensions','temporary','draft','needs_review','completion_draft','external_production'];
  category jsonb; prior_category jsonb; updated_categories jsonb;
  family jsonb; family_list jsonb; retained_families jsonb; members jsonb;
  category_members jsonb; added_members jsonb;
  actor public.profiles%rowtype; can_edit boolean; can_validate boolean; page text; machine jsonb;
begin
  if auth.uid() is null or not public.has_forage_app_access() then
    raise exception 'Authenticated approved device required' using errcode='42501';
  end if;
  select * into actor from public.profiles where id=auth.uid();
  if actor.role='visitor' then raise exception 'Read-only account' using errcode='42501'; end if;
  if jsonb_typeof(new.snapshot) is distinct from 'object' or octet_length(new.snapshot::text)>52428800 then
    raise exception 'Invalid snapshot size or shape' using errcode='22023';
  end if;
  if not (new.snapshot ? 'catalog_families') then
    family_list := case when tg_op = 'UPDATE'
      then coalesce(old.snapshot->'catalog_families','[]'::jsonb) else '[]'::jsonb end;
    retained_families := '[]'::jsonb;
    for family in select value from jsonb_array_elements(family_list) loop
      category_members := (family->>'category_ids')::jsonb;
      select coalesce(jsonb_agg(member.value order by member.position),'[]'::jsonb)
      into members
      from jsonb_array_elements_text(category_members)
        with ordinality as member(value,position)
      where exists (
        select 1 from jsonb_array_elements(new.snapshot->'categories') as c(entry)
        where c.entry->>'id' = member.value
      );
      retained_families := retained_families || jsonb_build_array(
        case when members = category_members then family
          else family || jsonb_build_object('category_ids',members::text) end
      );
    end loop;
    new.snapshot := new.snapshot || jsonb_build_object('catalog_families',retained_families);
  end if;
  if not (new.snapshot ?& tables) or exists(select 1 from jsonb_object_keys(new.snapshot) key where not key=any(tables)) then
    raise exception 'Unknown or missing tables' using errcode='22023';
  end if;
  -- Legacy clients omit families and may strip manufactured products from
  -- flat category memberships. Recover only those still in the catalog.
  if tg_op = 'UPDATE' then
    updated_categories := '[]'::jsonb;
    for category in select value from jsonb_array_elements(new.snapshot->'categories') loop
      if not (category ? 'families') then
        select value into prior_category
        from jsonb_array_elements(old.snapshot->'categories')
        where value->>'id' = category->>'id';
        if prior_category is not null then
          category_members := (category->>'product_ids')::jsonb;
          select coalesce(jsonb_agg(item.value order by item.position), '[]'::jsonb)
          into added_members
          from jsonb_array_elements_text((prior_category->>'product_ids')::jsonb)
            with ordinality as item(value, position)
          where not (category_members ? item.value)
            and exists (
              select 1 from jsonb_array_elements(new.snapshot->'products') p
              where p->>'id' = item.value and p->>'kind' = 'manufactured'
            );
          if added_members <> '[]'::jsonb then
            category_members := category_members || added_members;
            if category_members is not distinct from (prior_category->>'product_ids')::jsonb then
              category := category || jsonb_build_object('product_ids', prior_category->>'product_ids');
            else
              category := category || jsonb_build_object('product_ids', category_members::text);
            end if;
          end if;
          if prior_category ? 'families' then
            family_list := (prior_category->>'families')::jsonb;
            retained_families := '[]'::jsonb;
            for family in select value from jsonb_array_elements(family_list) loop
              select coalesce(jsonb_agg(item.value order by item.position), '[]'::jsonb)
              into members
              from jsonb_array_elements_text(family->'product_ids')
                with ordinality as item(value, position)
              where category_members ? item.value;
              retained_families := retained_families || jsonb_build_array(
                jsonb_set(family, '{product_ids}', members)
              );
            end loop;
            category := category || jsonb_build_object(
              'families', case when retained_families = family_list
                then prior_category->>'families' else retained_families::text end
            );
          end if;
        end if;
      end if;
      updated_categories := updated_categories || jsonb_build_array(category);
    end loop;
    new.snapshot := jsonb_set(new.snapshot, '{categories}', updated_categories);
  end if;

  can_validate := actor.role='admin' or (actor.role='validation' and 'validation'=any(actor.writable_pages) and 'validation'=any(actor.allowed_pages));
  foreach t in array tables loop
    if jsonb_typeof(new.snapshot->t) is distinct from 'array' or jsonb_array_length(new.snapshot->t)>100000 then
      raise exception 'Invalid table %',t using errcode='22023';
    end if;
    allowed := string_to_array(case t
      when 'products' then 'id,name,reference,width,length_meters,length_unit,thickness,manufactured,kind,diameter,diameter_is_external,diameter_calculated_from_dimensions,hose_unit,meters_per_piece,initial_stock,initial_depot_id,material_type,image,parent_product_id'
      when 'categories' then 'id,name,product_ids,image,families'
      when 'catalog_families' then 'id,name,category_ids'
      when 'machines' then 'id,name,copies,type,inputs,output,operator_ids,image,category_id,units,temporary,deadline,planned_pieces,hopper_pieces,temporary_input_product_id,temporary_source_depot_id,temporary_input_pieces'
      when 'operations' then 'id,machine_id,operator_id,pieces,hopper_pieces,started_at,finished_at,output_pieces,final_image,product_id,source_depot_id,output_depot_id,remainder_depot_id,machine_unit_number,remainder_image,needs_review,scrap_pieces,completion_draft,validated_at,output_product_id,external_production,remainder_pieces,scrap_depot_id,scrap_product_id,scrap_image'
      when 'stock_additions' then 'id,product_id,depot_id,pieces,receipt_number,supplier_id,return_purchase_id,quantity,unit,images,transport_charge,created_at,draft'
      when 'suppliers' then 'id,name,company,contact,images'
      when 'clients' then 'id,name,company,phone,ice,images'
      when 'sales' then 'id,product_id,depot_id,client_id,pieces,quantity,unit,images,transport_charge,created_at,draft'
      when 'competitors' then 'id,name'
      when 'transaction_payments' then 'id,sale_id,stock_addition_id,source,competitor_id,payment_mode,amount,created_at'
      when 'stock_transfers' then 'id,product_id,source_depot_id,destination_depot_id,pieces,created_at,draft'
      when 'sale_returns' then 'id,sale_id,product_id,depot_id,pieces,created_at,status'
      when 'operator_payments' then 'id,operator_id,amount,paid_at'
      when 'depots' then 'id,name,image' end,',');
    required := string_to_array(case t
      when 'products' then 'id,name,reference,width,length_meters,length_unit,thickness,manufactured,kind,diameter_is_external,diameter_calculated_from_dimensions,hose_unit,initial_stock,initial_depot_id,material_type'
      when 'categories' then 'id,name,product_ids'
      when 'catalog_families' then 'id,name,category_ids'
      when 'machines' then 'id,name,copies,type,inputs,output,operator_ids,units,temporary'
      when 'operations' then 'id,machine_id,operator_id,pieces,started_at,product_id,source_depot_id,machine_unit_number,needs_review,scrap_pieces,completion_draft,external_production,remainder_pieces'
      when 'stock_additions' then 'id,product_id,depot_id,pieces,receipt_number,images,transport_charge,created_at,draft'
      when 'suppliers' then 'id,name,company,contact,images'
      when 'clients' then 'id,name,company,phone,ice,images'
      when 'sales' then 'id,product_id,depot_id,client_id,pieces,quantity,unit,images,transport_charge,created_at,draft'
      when 'competitors' then 'id,name'
      when 'transaction_payments' then 'id,source,payment_mode,amount,created_at'
      when 'stock_transfers' then 'id,product_id,source_depot_id,destination_depot_id,pieces,created_at,draft'
      when 'sale_returns' then 'id,sale_id,product_id,depot_id,pieces,created_at,status'
      when 'operator_payments' then 'id,operator_id,amount,paid_at'
      when 'depots' then 'id,name' end,',');
    if exists(select 1 from jsonb_array_elements(new.snapshot->t) r group by r->>'id' having count(*)>1) then
      raise exception 'Duplicate record identifiers' using errcode='22023';
    end if;
    before_rows := case when tg_op='INSERT' then '[]'::jsonb else old.snapshot->t end;
    for row_new in select value from jsonb_array_elements(new.snapshot->t) loop
      if jsonb_typeof(row_new) is distinct from 'object' or coalesce(length(row_new->>'id'),0) not between 1 and 128 then
        raise exception 'Invalid record' using errcode='22023';
      end if;
      if t='stock_additions' then
        if not (row_new ?& required) then raise exception 'Required fields missing in %',t using errcode='22023'; end if;
        if jsonb_typeof(row_new->'id') <> 'number' or (row_new->>'id') !~ '^[0-9]+$' then
          raise exception 'Invalid stock identifier' using errcode='22023';
        end if;
      elsif jsonb_typeof(row_new->'id') <> 'string' then
        raise exception 'Invalid identifier type' using errcode='22023';
      end if;
      if not (row_new ?& required) or exists(select 1 from unnest(required) key where row_new->key='null'::jsonb) then
        raise exception 'Required fields missing in %',t using errcode='22023';
      end if;
      if t = 'categories' and row_new ? 'families' then
        if jsonb_typeof(row_new->'families') is distinct from 'string'
          or octet_length(row_new->>'families') > 2097152 then
          raise exception 'Invalid family list' using errcode='22023';
        end if;
        family_list := (row_new->>'families')::jsonb;
        category_members := (row_new->>'product_ids')::jsonb;
        if jsonb_typeof(family_list) is distinct from 'array' then
          raise exception 'Family list must be an array' using errcode='22023';
        end if;
        for family in select value from jsonb_array_elements(family_list) loop
          if jsonb_typeof(family) is distinct from 'object' then
            raise exception 'Invalid family record' using errcode='22023';
          end if;
          if not (family ?& array['id','name','product_ids'])
            or (family - array['id','name','product_ids']) <> '{}'::jsonb
            or jsonb_typeof(family->'id') is distinct from 'string'
            or length(btrim(family->>'id')) not between 1 and 128
            or jsonb_typeof(family->'name') is distinct from 'string'
            or length(btrim(family->>'name')) not between 1 and 120
            or (family->>'name') ~ '[<>[:cntrl:]]'
            or jsonb_typeof(family->'product_ids') is distinct from 'array' then
            raise exception 'Invalid family record' using errcode='22023';
          end if;
          if exists (
            select 1 from jsonb_array_elements(family->'product_ids') member
            where jsonb_typeof(member) <> 'string'
              or not (category_members ? (member #>> '{}'))
          ) then
            raise exception 'Family members must belong to their category' using errcode='22023';
          end if;
        end loop;
        if exists (
          select 1 from jsonb_array_elements(family_list) f group by f->>'id' having count(*) > 1
        ) or exists (
          select 1 from jsonb_array_elements(family_list) f
          group by lower(btrim(f->>'name')) having count(*) > 1
        ) or exists (
          select 1 from jsonb_array_elements(family_list) f
          cross join lateral jsonb_array_elements_text(f->'product_ids') member
          group by member having count(*) > 1
        ) then
          raise exception 'Duplicate family or family member' using errcode='22023';
        end if;
      end if;
      for field in select * from jsonb_each(row_new) loop
        k := field.key;
        if not k=any(allowed) then raise exception 'Unknown field %',k using errcode='22023'; end if;
        if k='families' or field.value='null'::jsonb then continue; end if;
        if k=any(numeric_fields) or k=any(integer_fields) or k=any(flags) then
          if jsonb_typeof(field.value) <> 'number' then raise exception 'Invalid numeric field %',k using errcode='22023'; end if;
          if abs((field.value::text)::numeric)>9007199254740991 then raise exception 'Numeric range exceeded' using errcode='22023'; end if;
          if (k=any(integer_fields) or k=any(flags)) and field.value::text !~ '^-?[0-9]+$' then raise exception 'Integer required' using errcode='22023'; end if;
          if k=any(flags) and field.value::text not in ('0','1') then raise exception 'Invalid flag' using errcode='22023'; end if;
          if (field.value::text)::numeric < 0 and not(t='stock_additions' and k in ('pieces','quantity')) then
            raise exception 'Negative value rejected' using errcode='22023';
          end if;
        elsif k <> 'id' then
          if jsonb_typeof(field.value) <> 'string' then raise exception 'String required for %',k using errcode='22023'; end if;
          if k in ('images','units','inputs','operator_ids','product_ids','category_ids') then
            if octet_length(row_new->>k)>2097152 or jsonb_typeof((row_new->>k)::jsonb)<>'array' then
              raise exception 'Invalid list field' using errcode='22023';
            end if;
            for list_item in select value from jsonb_array_elements((row_new->>k)::jsonb) loop
              if k in ('inputs','operator_ids','product_ids','category_ids') and
                  (jsonb_typeof(list_item)<>'string' or length(list_item#>>'{}') not between 1 and 128) then
                raise exception 'Invalid list identifier' using errcode='22023';
              end if;
              if k='images' and (jsonb_typeof(list_item)<>'string' or octet_length(list_item#>>'{}')>200000
                  or (list_item#>>'{}') !~ '^[A-Za-z0-9+/]*={0,2}$') then
                raise exception 'Invalid list image' using errcode='22023';
              end if;
            end loop;
          elsif k in ('image','final_image','scrap_image','remainder_image') then
            if octet_length(row_new->>k)>200000 or (row_new->>k) !~ '^[A-Za-z0-9+/]*={0,2}$' then
              raise exception 'Invalid or oversized image' using errcode='22023';
            end if;
          elsif length(row_new->>k)>2000 or (row_new->>k) ~ '[<>[:cntrl:]]' then
            raise exception 'Invalid plain-text field' using errcode='22023';
          end if;
        end if;
      end loop;
      if t='catalog_families' and (
        length(btrim(row_new->>'name')) not between 1 and 120 or exists (
          select 1 from jsonb_array_elements_text((row_new->>'category_ids')::jsonb) member
          where not exists (
            select 1 from jsonb_array_elements(new.snapshot->'categories') as c(entry)
            where c.entry->>'id' = member
          )
        )
      ) then
        raise exception 'Invalid catalog family or category membership' using errcode='22023';
      end if;
      if t in ('operations','sales','stock_transfers','sale_returns') and coalesce((row_new->>'pieces')::numeric,0)<=0 then
        raise exception 'Positive quantity required' using errcode='22023';
      end if;
      if t='stock_transfers' and row_new->>'source_depot_id'=row_new->>'destination_depot_id' then raise exception 'Distinct depots required'; end if;
      if t='sale_returns' and coalesce(row_new->>'status','') not in ('pending','approved','rejected') then raise exception 'Invalid return status'; end if;
      if t='machines' and ((row_new->>'copies')::integer < 1 or row_new->>'type' not in ('standard','roulage')) then
        raise exception 'Invalid machine configuration' using errcode='22023';
      end if;
      if t='operations' and row_new->>'finished_at' is not null then
        select value into machine from jsonb_array_elements(new.snapshot->'machines') where value->>'id'=row_new->>'machine_id';
        if coalesce((row_new->>'output_pieces')::numeric,-1)<0
           or (row_new->>'finished_at')::numeric<(row_new->>'started_at')::numeric
           or (machine is not null and
             (row_new->>'output_pieces')::numeric * case when machine->>'type'='roulage' then coalesce((row_new->>'hopper_pieces')::numeric,0) else 1 end
               + (row_new->>'remainder_pieces')::numeric + (row_new->>'scrap_pieces')::numeric <> (row_new->>'pieces')::numeric) then
          raise exception 'Invalid production balance or dates' using errcode='22023';
        end if;
      end if;
    end loop;

    if t='catalog_families' and (exists (
      select 1 from jsonb_array_elements(new.snapshot->t) as f(entry)
      group by lower(btrim(f.entry->>'name')) having count(*) > 1
    ) or exists (
      select 1 from jsonb_array_elements(new.snapshot->t) as f(entry)
      cross join lateral jsonb_array_elements_text((f.entry->>'category_ids')::jsonb) member
      group by member having count(*) > 1
    )) then
      raise exception 'Duplicate catalog family or category membership' using errcode='22023';
    end if;
    -- Compare rows by ID, not array order. Every changed record is authorized.
    for changed in
      select a.value a,b.value b from jsonb_array_elements(new.snapshot->t) a
      full join jsonb_array_elements(coalesce(before_rows,'[]')) b on a.value->>'id'=b.value->>'id'
      where a.value is distinct from b.value
    loop
      row_new:=changed.a; row_old:=changed.b;
      if actor.role='admin' then continue; end if;
      page:=case when t in ('products','categories','catalog_families') then 'products'
        when t='machines' then 'machines' when t='operator_payments' then 'team' else 'stock' end;
      can_edit:=page=any(actor.writable_pages) and page=any(actor.allowed_pages);
      if t='operations' then
        if can_validate and row_old->>'completion_draft'='1' and row_old->>'validated_at' is null then
          if row_new is not null and (row_new->>'operator_id' is distinct from row_old->>'operator_id'
            or row_new->>'machine_id' is distinct from row_old->>'machine_id') then
            raise exception 'Operation identity cannot change' using errcode='42501';
          end if;
          continue;
        end if;
        if actor.role<>'operator' or not ('machines'=any(actor.writable_pages)) or not ('machines'=any(actor.allowed_pages)) or row_new is null
           or row_new->>'operator_id' is distinct from auth.uid()::text
           or row_new->>'validated_at' is not null or coalesce(row_new->>'external_production','0')<>'0'
           or (row_old is not null and (row_old->>'validated_at' is not null or row_old->>'completion_draft'='1')) then
          raise exception 'Operation write denied' using errcode='42501';
        end if;
        select value into machine from jsonb_array_elements(new.snapshot->'machines') where value->>'id'=row_new->>'machine_id';
        if machine is null or not ((machine->>'operator_ids')::jsonb ? auth.uid()::text) then
          raise exception 'Assigned operator required' using errcode='42501';
        end if;
        if row_old is not null and (row_new - array['finished_at','output_pieces','final_image','remainder_image','scrap_image','scrap_pieces','completion_draft','output_depot_id','remainder_depot_id','remainder_pieces','scrap_depot_id','scrap_product_id','output_product_id'])
          is distinct from (row_old - array['finished_at','output_pieces','final_image','remainder_image','scrap_image','scrap_pieces','completion_draft','output_depot_id','remainder_depot_id','remainder_pieces','scrap_depot_id','scrap_product_id','output_product_id']) then
          raise exception 'Started operation fields are immutable' using errcode='42501';
        end if;
        if row_new->>'finished_at' is not null and row_new->>'completion_draft' is distinct from '1' then
          raise exception 'Validator approval required' using errcode='42501';
        end if;
        continue;
      end if;
      -- Production may create a zero-stock product variant but cannot change
      -- an existing product or create stock without a validated operation.
      if t='products' and actor.role='operator' and row_old is null and row_new is not null
        and row_new->>'initial_stock'='0' and exists(
          select 1 from jsonb_array_elements(new.snapshot->'operations') o
          where o->>'operator_id'=auth.uid()::text and o->>'validated_at' is null
            and (o->>'output_product_id'=row_new->>'id' or o->>'scrap_product_id'=row_new->>'id')) then continue; end if;
      if t='machines' then
        -- Validators may remove only the temporary machine of a processed draft.
        if can_validate and row_new is null and row_old->>'temporary'='1' and exists(
          select 1 from jsonb_array_elements(coalesce(old.snapshot->'operations','[]')) o
          where o->>'machine_id'=row_old->>'id' and o->>'completion_draft'='1') then continue; end if;
        -- Do not let an operator assign arbitrary machines to themselves.
        raise exception 'Machine administration required' using errcode='42501';
      end if;
      if can_validate and t in ('stock_additions','sales','stock_transfers','sale_returns')
        and (row_old->>'draft'='1' or row_old->>'status'='pending') then continue; end if;
      if not can_edit or t in ('operator_payments','transaction_payments') then
        raise exception 'Table write denied: %',t using errcode='42501';
      end if;
      if t='products' and row_new is not null and (
          (row_old is null and coalesce(row_new->>'initial_stock','0') <> '0') or
          (row_old is not null and (row_new->'initial_stock' is distinct from row_old->'initial_stock'
            or row_new->'initial_depot_id' is distinct from row_old->'initial_depot_id'))) then
        raise exception 'Initial stock administration required' using errcode='42501';
      end if;
      if t in ('stock_additions','sales','stock_transfers')
        and (row_old->>'draft'='0' or row_new->>'draft' is distinct from '1') then
        raise exception 'Only pending drafts may be edited' using errcode='42501';
      end if;
      if t='sale_returns' and (row_old->>'status' in ('approved','rejected') or row_new->>'status' is distinct from 'pending') then
        raise exception 'Only pending returns may be edited' using errcode='42501';
      end if;
    end loop;
  end loop;
  new.updated_at:=now();
  return new;
end;
$$;
revoke all on function public.validate_workshop_snapshot() from public, anon, authenticated;

-- Old apps require the original category columns on download.
create or replace function public.get_forage_workshop(
  p_include_families boolean, p_include_catalog_families boolean
)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  if auth.uid() is null or not public.has_forage_app_access() then
    raise exception 'Approved device required' using errcode='42501';
  end if;
  select snapshot into result from public.workshop_snapshots where id='main';
  if result is not null and not public.is_admin() then
    result:=result || '{"operator_payments":[],"transaction_payments":[]}'::jsonb;
  end if;
  if result is not null and not coalesce(p_include_families, false) then
    result := jsonb_set(result, '{categories}', (
      select coalesce(jsonb_agg(value - 'families' order by position), '[]'::jsonb)
      from jsonb_array_elements(result->'categories') with ordinality as rows(value, position)
    ));
  end if;
  if result is not null then
    if coalesce(p_include_catalog_families, false) then
      if not (result ? 'catalog_families') then
        result := result || '{"catalog_families":[]}'::jsonb;
      end if;
    else
      result := result - 'catalog_families';
    end if;
  end if;
  return result;
end;
$$;

create or replace function public.get_forage_workshop(p_include_families boolean)
returns jsonb language sql stable security definer set search_path='' as $$
  select public.get_forage_workshop(p_include_families, false);
$$;

create or replace function public.get_forage_workshop()
returns jsonb language sql stable security definer set search_path='' as $$
  select public.get_forage_workshop(false);
$$;

revoke all on function public.get_forage_workshop(boolean) from public, anon, authenticated;
grant execute on function public.get_forage_workshop(boolean) to authenticated;
revoke all on function public.get_forage_workshop(boolean,boolean) from public, anon, authenticated;
grant execute on function public.get_forage_workshop(boolean,boolean) to authenticated;
notify pgrst, 'reload schema';
commit;
