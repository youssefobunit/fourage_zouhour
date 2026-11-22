import { readFileSync, readdirSync } from 'node:fs';
import assert from 'node:assert/strict';
import { PGlite } from '../../.security-tools/node_modules/@electric-sql/pglite/dist/index.js';

process.on('uncaughtException', (error) => {
  console.error(error.message, error.code ?? '', error.detail ?? '');
  process.exit(1);
});

const db = new PGlite();
await db.exec(`
  create role anon; create role authenticated; create role service_role bypassrls;
  create schema auth;
  create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}');
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
  grant usage on schema public,auth to anon,authenticated,service_role;
  grant execute on function auth.uid() to public;
  alter default privileges in schema public grant all on tables to anon,authenticated,service_role;
  alter default privileges in schema public grant execute on functions to anon,authenticated,service_role;
`);
const migrations = readdirSync('supabase/migrations').filter(f=>f.endsWith('.sql')).sort();
for (const file of migrations) await db.exec(readFileSync(`supabase/migrations/${file}`,'utf8'));
// Re-running the security migrations must not duplicate policies or lose data.
for (const file of migrations.filter(f=>f >= '202611170001')) await db.exec(readFileSync(`supabase/migrations/${file}`,'utf8'));
const admin='10000000-0000-0000-0000-000000000001';
const worker='10000000-0000-0000-0000-000000000002';
const visitor='10000000-0000-0000-0000-000000000003';
const outsider='10000000-0000-0000-0000-000000000004';
const owner='10000000-0000-0000-0000-000000000005';
const device='device-secret-012345678901234567890';
const nonce='login-nonce-0123456789';
for (const [id,role] of [[admin,'admin'],[worker,'operator'],[visitor,'visitor']]) {
  await db.query(`insert into auth.users(id,email,raw_app_meta_data) values($1,$2,'{"forage_managed":true}')`,[id,`${role}@example.com`]);
  await db.query(`update public.profiles set role=$2,allowed_pages=case when $2='operator' then array['machines'] else '{}' end,writable_pages=case when $2='operator' then array['machines'] else '{}' end where id=$1`,[id,role]);
}
await db.query(`insert into auth.users(id,email,raw_user_meta_data) values($1,'outside@example.com','{"role":"admin","forage_managed":true}')`,[outsider]);
assert.equal((await db.query('select status from profiles where id=$1',[outsider])).rows[0].status,'dismissed');
let checks=1;
async function asUser(user,sql,params=[],role='authenticated') {
  await db.exec('begin');
  try {
    await db.query(`select set_config('request.jwt.claim.sub',$1,true),set_config('request.headers',$2,true)`,
      [user,JSON.stringify({'x-forage-device-id':device,'x-forage-login-nonce':nonce})]);
    await db.exec(`set local role ${role}`);
    const result=await db.query(sql,params);
    await db.exec('commit'); return result;
  } catch(error) { await db.exec('rollback'); throw error; }
}
async function denied(label,fn) {
  await assert.rejects(fn, undefined, label); checks++; console.log(`PASS ${label}`);
}
await denied('anonymous RPC',()=>asUser('',`select public.record_forage_device_login('Phone',$1)`,[nonce],'anon'));
await denied('device self-approval via login history',()=>asUser(worker,`select public.record_forage_device_login('Phone',$1)`,[nonce]));
assert.equal((await db.query('select count(*)::int n from trusted_devices where user_id=$1',[worker])).rows[0].n,0);
await denied('direct device insert',()=>asUser(worker,`insert into trusted_devices(user_id,device_id) values($1,$2)`,[worker,device]));
const request=(await asUser(worker,`select request_device_access($1,'Phone',$2) result`,[device,nonce])).rows[0].result;
assert.equal(request.status,'pending'); checks++;
await denied('worker approves own device',()=>asUser(worker,`select decide_device_access_request($1,true,false)`,[request.request_id]));
await asUser(admin,`select decide_device_access_request($1,true,false)`,[request.request_id]);
await asUser(worker,`select record_forage_device_login('Phone',$1)`,[nonce]);
await asUser(worker,`select record_forage_device_login('Phone',$1)`,[nonce]);
assert.equal((await db.query('select count(*)::int n from forage_device_sessions where user_id=$1',[worker])).rows[0].n,1); checks++;
const tables=['products','categories','machines','operations','stock_additions','suppliers','clients','sales','competitors','transaction_payments','stock_transfers','sale_returns','operator_payments','depots'];
const snapshot=Object.fromEntries(tables.map(t=>[t,[]]));
snapshot.machines=[{id:'machine-1',name:'Machine',operator_ids:JSON.stringify([worker]),copies:1,type:'standard',inputs:'["p-1"]',output:'p-2',units:'[]',temporary:0}];
snapshot.operator_payments=[{id:'pay-1',operator_id:worker,amount:100,paid_at:1700000000000}];
await asUser(admin,`insert into workshop_snapshots(id,snapshot) values('main',$1)`,[JSON.stringify(snapshot)]); checks++;
assert.equal((await asUser(outsider,'select * from workshop_snapshots')).rows.length,0); checks++;
await denied('unapproved workshop RPC',()=>asUser(outsider,'select get_forage_workshop()'));
assert.equal((await asUser(worker,'select * from workshop_snapshots')).rows.length,0); checks++;
assert.deepEqual((await asUser(worker,'select get_forage_workshop() data')).rows[0].data.operator_payments,[]); checks++;
async function changeWorkshop(user, modify) {
  const data=(await asUser(user,'select get_forage_workshop() data')).rows[0].data;
  modify(data);
  return asUser(user,'select save_forage_workshop($1)',[JSON.stringify(data)]);
}
// RLS UPDATE hides forbidden rows rather than necessarily raising an error.
assert.equal((await asUser(worker,"update profiles set role='admin' where id=$1 returning id",[worker])).rows.length,0); checks++;
await denied('last admin demotion',()=>asUser(admin,"update profiles set role='visitor' where id=$1",[admin]));
await denied('malformed snapshot',()=>asUser(admin,"update workshop_snapshots set snapshot='[]'"));
await denied('unknown table / credential upload',()=>asUser(admin,"update workshop_snapshots set snapshot=snapshot || '{\"users\":[]}'"));
await denied('operator machine reassignment',()=>changeWorkshop(worker,s=>s.machines[0].operator_ids='[]'));
const operation={id:'op-1',machine_id:'machine-1',operator_id:worker,product_id:'p-1',pieces:3,started_at:1700000000000,completion_draft:0,validated_at:null,finished_at:null,
source_depot_id:'general-depot',machine_unit_number:1,needs_review:0,scrap_pieces:0,external_production:0,remainder_pieces:0};
await changeWorkshop(worker,s=>s.operations=[operation]); checks++;
await denied('operator self-validation',()=>changeWorkshop(worker,s=>s.operations[0].validated_at=1700000000001));
await denied('negative quantity',()=>changeWorkshop(worker,s=>s.operations[0].pieces=-1));
await denied('missing required fields',()=>changeWorkshop(admin,s=>delete s.operations[0].product_id));
await denied('null required fields',()=>changeWorkshop(admin,s=>s.operations[0].product_id=null));
await denied('unbalanced production',()=>changeWorkshop(worker,s=>Object.assign(s.operations[0],{finished_at:1700000000001,completion_draft:1,output_pieces:4})));
await denied('private data injection',()=>changeWorkshop(worker,s=>s.operator_payments=snapshot.operator_payments));
assert.equal((await asUser(admin,'select get_forage_workshop() data')).rows[0].data.operator_payments[0].amount,100); checks++;
await changeWorkshop(worker,s=>Object.assign(s.operations[0],{finished_at:1700000000001,completion_draft:1,output_pieces:3})); checks++;
await denied('stored markup',()=>asUser(admin,"update workshop_snapshots set snapshot=jsonb_set(snapshot,'{machines,0,name}','\"<script>alert(1)</script>\"')"));
await denied('security log deletion',()=>asUser(admin,'delete from forage_security_events'));
await denied('rate limiter is server only',()=>asUser(worker,'select consume_forage_admin_request($1)',[worker]));
for(let i=0;i<10;i++) assert.equal((await asUser('', 'select consume_forage_admin_request($1) ok',[admin],'service_role')).rows[0].ok,true);
assert.equal((await asUser('', 'select consume_forage_admin_request($1) ok',[admin],'service_role')).rows[0].ok,false); checks++;
await asUser(admin,"select set_forage_device_status(id,'blocked') from trusted_devices where user_id=$1",[worker]);
await denied('blocked device cannot record login',()=>asUser(worker,`select record_forage_device_login('Phone',$1)`,[nonce]));
assert.equal((await asUser(worker,'select * from workshop_snapshots')).rows.length,0); checks++;
await db.query(`insert into auth.users(id,email,raw_app_meta_data) values($1,'owner@younes.com','{"forage_managed":true}')`,[owner]);
await db.query(`update public.profiles set role='admin',allowed_pages=array['dashboard','products','stock','machines','team','validation','analytics'],writable_pages=array['dashboard','products','stock','machines','team','validation','analytics'] where id=$1`,[owner]);
assert.equal((await asUser(owner,'select is_forage_owner() owner')).rows[0].owner,true); checks++;
await denied('non-owner admin permanent deletion',()=>changeWorkshop(admin,s=>s.machines=[]));
await changeWorkshop(owner,s=>s.machines=[]); checks++;
const product = {
  id:'catalog-item',name:'Pièce',reference:'CAT-1',width:0,length_meters:0,
  length_unit:'meter',thickness:0,manufactured:1,kind:'manufactured',
  diameter_is_external:1,diameter_calculated_from_dimensions:0,hose_unit:'piece',
  initial_stock:0,initial_depot_id:'general-depot',material_type:'steel'
};
const family = {id:'family-1',name:'Forets',product_ids:[product.id]};
await changeWorkshop(owner,s=>{
  s.products=[product];
  s.categories=[{
    id:'category-1',name:'Forage',product_ids:JSON.stringify([product.id]),
    families:JSON.stringify([family])
  }];
});
const readCategory = async () =>
  (await asUser(owner,'select get_forage_workshop(true) data')).rows[0].data.categories[0];
assert.deepEqual(JSON.parse((await readCategory()).families),[family]); checks++;
await changeWorkshop(owner,s=>{
  assert.equal(s.categories[0].families,undefined);
  // Old app versions can drop manufactured IDs from the flat category list.
  s.categories[0].product_ids='[]';
});
assert.deepEqual(JSON.parse((await readCategory()).product_ids),[product.id]); checks++;
assert.deepEqual(JSON.parse((await readCategory()).families),[family]); checks++;
await denied('unapproved family catalog read',()=>asUser(outsider,'select get_forage_workshop(true)'));
await denied('family product outside its category',()=>changeWorkshop(owner,s=>{
  s.categories[0].families=JSON.stringify([{...family,product_ids:['different-item']}]);
}));
await denied('product assigned to two families in one category',()=>changeWorkshop(owner,s=>{
  s.categories[0].families=JSON.stringify([family,{...family,id:'family-2',name:'Autres'}]);
}));
await denied('stored family markup',()=>changeWorkshop(owner,s=>{
  s.categories[0].families=JSON.stringify([{...family,name:'<script>'}]);
}));
const catalogFamily={id:'root-family',name:'Équipement de forage',category_ids:'["category-1"]'};
await changeWorkshop(owner,s=>s.catalog_families=[catalogFamily]);
const readCatalog = async () =>
  (await asUser(owner,'select get_forage_workshop(true,true) data')).rows[0].data;
assert.deepEqual((await readCatalog()).catalog_families,[catalogFamily]); checks++;
await changeWorkshop(owner,s=>{
  assert.equal(s.catalog_families,undefined);
  s.categories[0].name='Forage et accessoires';
});
assert.deepEqual((await readCatalog()).catalog_families,[catalogFamily]); checks++;
await denied('unknown category in a catalog family',()=>changeWorkshop(owner,s=>{
  s.catalog_families=[{...catalogFamily,category_ids:'["not-a-category"]'}];
}));
await denied('one category assigned to two catalog families',()=>changeWorkshop(owner,s=>{
  s.catalog_families=[catalogFamily,{...catalogFamily,id:'another',name:'Autres'}];
}));
console.log(`Passed ${checks} database security checks and migration replay.`);
await db.close();
