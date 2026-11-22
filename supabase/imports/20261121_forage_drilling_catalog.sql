-- Import the supplied drilling catalog once in the FORAGE project's SQL Editor
-- as postgres. Re-running it preserves existing products and category images.
do $catalog$
declare
  owner_id uuid;
  workshop jsonb;
  products jsonb;
  categories jsonb;
  family record;
  item record;
  category_row jsonb;
  product_ids jsonb;
  product_id text;
  catalog_id text;
  product_name text;
  imported_count integer := 0;
  category_count integer := 0;
begin
  if current_user <> 'postgres' then
    raise exception 'Exécutez cet import avec le rôle postgres du SQL Editor.';
  end if;

  -- Set the actor only for this administrative transaction. Leave the
  -- workshop RPC, validation triggers and permissions in force.
  select id into strict owner_id
  from public.profiles
  where lower(email) = 'owner@younes.com' and role = 'admin' and status = 'active';
  perform set_config('request.jwt.claim.sub', owner_id::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', owner_id, 'role', 'authenticated')::text,
    true
  );

  -- Use the same lock as the app's save RPC, before reading existing records.
  perform pg_advisory_xact_lock(710170002);
  select snapshot into workshop
  from public.workshop_snapshots where id = 'main' for update;
  if workshop is null
    or jsonb_typeof(workshop->'products') is distinct from 'array'
    or jsonb_typeof(workshop->'categories') is distinct from 'array' then
    raise exception 'Ouvrez et synchronisez d’abord l’atelier FORAGE.';
  end if;
  products := workshop->'products';
  categories := workshop->'categories';

  for family in
    select * from (values
      ('hammer', 'Marteau DHD'),
      ('dth', 'Taillant DTH'),
      ('tricone', 'Tricone Bit')
    ) as names(code, name)
  loop
    category_row := null;
    select value into category_row
    from jsonb_array_elements(categories)
    where value->>'id' = 'forage-drilling-' || family.code;
    if category_row is null then
      select value into category_row
      from jsonb_array_elements(categories)
      where lower(btrim(value->>'name')) = lower(family.name)
      order by value->>'id'
      limit 1;
    end if;
    if category_row is null then
      category_row := jsonb_build_object(
        'id', 'forage-drilling-' || family.code, 'name', family.name, 'image', ''
      );
      category_count := category_count + 1;
    end if;
    -- The mobile app stores this array as JSON text inside the snapshot.
    product_ids := coalesce((category_row->>'product_ids')::jsonb, '[]'::jsonb);

    for item in
      select * from (values
        -- Source references, inches, diameter in mm, model, Tricone number.
        ('hammer', 'HAM-001', '4', 101.6, 'DTH Hammer', null::integer),
        ('hammer', 'HAM-002', '10', 254, 'DTH Hammer', null),
        ('hammer', 'HAM-003', '8', 203.2, 'DTH Hammer', null),
        ('hammer', 'HAM-004', '6', 152.4, 'DTH Hammer', null),
        ('dth', 'DTH-115-DHD340', '4-1/2', 115, 'DHD340', null),
        ('dth', 'DTH-152-DHD360', '6', 152, 'DHD360', null),
        ('dth', 'DTH-160-DHD360', '6-1/4', 160, 'DHD360', null),
        ('dth', 'DTH-165-DHD360', '6-1/2', 165, 'DHD360', null),
        ('dth', 'DTH-165-SD6', '6-1/2', 165, 'SD6', null),
        ('dth', 'DTH-171-DHD360', '6-3/4', 171, 'DHD360', null),
        ('dth', 'DTH-196-DHD360', '7-3/4', 196, 'DHD360', null),
        ('dth', 'DTH-203-DHD360', '8', 203, 'DHD360', null),
        ('dth', 'DTH-203-DHD380', '8', 203, 'DHD380', null),
        ('dth', 'DTH-204-DHD380', '8', 204, 'DHD380', null),
        ('dth', 'DTH-216-DHD360', '8-1/2', 216, 'DHD360', null),
        ('dth', 'DTH-216-DHD380', '8-1/2', 216, 'DHD380', null),
        ('dth', 'DTH-216-SD8', '8-1/2', 216, 'SD8', null),
        ('dth', 'DTH-222-DHD380', '8-3/4', 222, 'DHD380', null),
        ('dth', 'DTH-225-DHD360', '8-7/8', 225, 'DHD360', null),
        ('dth', 'DTH-235-DHD380', '9-1/4', 235, 'DHD380', null),
        ('dth', 'DTH-267-DHD380', '10-1/2', 267, 'DHD380', null),
        ('dth', 'DTH-292-DHD380', '11-1/2', 292, 'DHD380', null),
        ('dth', 'DTH-305-DHD380', '12', 305, 'DHD380', null),
        ('dth', 'DTH-311-SD8', '12-1/4', 311, 'SD8', null),
        ('dth', 'DTH-311-SD10', '12-1/4', 311, 'SD10', null),
        ('dth', 'DTH-311-DHD380', '12-1/4', 311, 'DHD380', null),
        ('dth', 'DTH-318-SD10', '12-1/2', 318, 'SD10', null),
        ('dth', 'DTH-318-DHD380', '12-1/2', 318, 'DHD380', null),
        ('dth', 'DTH-356-SD10', '14', 356, 'SD10', null),
        ('dth', 'DTH-381-SD10', '15', 381, 'SD10', null),
        ('dth', 'DTH-393-SD10', '15-1/2', 393, 'SD10', null),
        ('tricone', 'TRI-15-SGA515GTC', '15', 381, 'SGA515GTC', 515),
        ('tricone', 'TRI-15-SGA535GKTC', '15', 381, 'SGA535GKTC', 535),
        ('tricone', 'TRI-17-SGA535GTC', '17', 431.8, 'SGA535GTC', 535),
        ('tricone', 'TRI-13-3-4-DHA517GKT', '13-3/4', 349.25, 'DHA517GKT', 517),
        ('tricone', 'TRI-14-3-4-SGA515GXT', '14-3/4', 374.65, 'SGA515GXT', 515),
        ('tricone', 'TRI-14-3-4-SGA535GXTC', '14-3/4', 374.65, 'SGA535GXTC', 535),
        ('tricone', 'TRI-15-1-2-SGA515GXTC', '15-1/2', 393.7, 'SGA515GXTC', 515),
        ('tricone', 'TRI-15-1-2-SGA535GXTC', '15-1/2', 393.7, 'SGA535GXTC', 535),
        ('tricone', 'TRI-17-1-2-SGA535XTC', '17-1/2', 444.5, 'SGA535XTC', 535),
        ('tricone', 'TRI-3-1-2-631', '3-1/2', 88.9, '631', 631),
        ('tricone', 'TRI-7-1-2-FA535G', '7-1/2', 190.5, 'FA535G', 537),
        ('tricone', 'TRI-8-1-2-IADC217G', '8-1/2', 215.9, 'IADC217G', 217),
        ('tricone', 'TRI-8-1-2-DHV537GKT', '8-1/2', 215.9, 'DHV537GKT', 537),
        ('tricone', 'TRI-9-7-8-IADC115G', '9-7/8', 250.825, 'IADC115G', 115),
        ('tricone', 'TRI-9-7-8-DHA537GX', '9-7/8', 250.825, 'DHA537GX', 537),
        ('tricone', 'TRI-4-1-2-537', '4-1/2', 114.3, null, 537),
        ('tricone', 'TRI-9-5-8-537', '9-5/8', 244.475, null, 537)
      ) as entries(code, reference, inches, diameter_mm, model, tool_number)
      where code = family.code
    loop
      catalog_id := 'forage-drilling-' || lower(item.reference);
      product_id := null;
      select value->>'id' into product_id
      from jsonb_array_elements(products)
      where value->>'id' = catalog_id;
      if product_id is null then
        select value->>'id' into product_id
        from jsonb_array_elements(products)
        where lower(btrim(value->>'reference')) = lower(item.reference)
          and value->>'kind' = 'diameter'
          and (value->>'diameter')::numeric = item.diameter_mm
        order by value->>'id'
        limit 1;
      end if;
      if product_id is null then
        if exists (
          select 1 from jsonb_array_elements(products)
          where lower(btrim(value->>'reference')) = lower(item.reference)
        ) then
          raise exception 'Référence déjà utilisée : %', item.reference;
        end if;
        product_id := catalog_id;
        product_name := concat_ws(' · ',
          case when family.code = 'dth'
            then format('%s Ø %s mm (%s")', family.name, item.diameter_mm, item.inches)
            else format('%s Ø %s"', family.name, item.inches)
          end,
          item.model,
          case when item.tool_number is not null then 'n° ' || item.tool_number end
        );
        products := products || jsonb_build_array(jsonb_build_object(
          'id', product_id, 'name', product_name, 'reference', item.reference,
          'kind', 'diameter', 'diameter', item.diameter_mm,
          'diameter_is_external', 1, 'diameter_calculated_from_dimensions', 0,
          'width', 0, 'length_meters', 0, 'length_unit', 'meter', 'thickness', 0,
          'manufactured', 0, 'hose_unit', 'piece', 'meters_per_piece', null,
          'initial_stock', 0, 'initial_depot_id', 'general-depot',
          'material_type', 'steel', 'image', null, 'parent_product_id', null
        ));
        imported_count := imported_count + 1;
      end if;
      if not (product_ids ? product_id) then
        product_ids := product_ids || jsonb_build_array(product_id);
      end if;
    end loop;

    category_row := category_row || jsonb_build_object('product_ids', product_ids::text);
    if exists (
      select 1 from jsonb_array_elements(categories)
      where value->>'id' = category_row->>'id'
    ) then
      select jsonb_agg(
        case when value->>'id' = category_row->>'id' then category_row else value end
        order by position
      ) into categories
      from jsonb_array_elements(categories) with ordinality as entries(value, position);
    else
      categories := categories || jsonb_build_array(category_row);
    end if;
  end loop;

  if products is distinct from workshop->'products'
    or categories is distinct from workshop->'categories' then
    perform public.save_forage_workshop(
      workshop || jsonb_build_object('products', products, 'categories', categories)
    );
  end if;
  raise notice 'Import FORAGE terminé : % nouveaux produits, % nouvelles catégories.',
    imported_count, category_count;
end
$catalog$;
