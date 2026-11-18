import test from 'node:test';
import assert from 'node:assert/strict';
import { validateUser, readBoundedJson } from '../../supabase/functions/admin-create-user/validation.mjs';

const valid = () => ({ username:'worker.one', email:'worker@example.com', fullName:'Ouvrier Un',
  password:'Long_password_2026', role:'operator', allowedPages:['dashboard','machines'], writablePages:['machines'] });
test('accepts a correctly scoped account', () => assert.equal(validateUser(valid()).role,'operator'));
for (const [label, change] of Object.entries({
  'admin escalation': {role:'admin'}, 'unknown field': {isAdmin:true},
  'XSS name': {fullName:'<script>alert(1)</script>'}, 'SQL username': {username:"x' OR 1=1--"},
  'excessive rights': {writablePages:['stock']}, 'readonly visitor': {role:'visitor'},
  'weak password': {password:'password'}, 'bcrypt byte limit': {password:'A1a'+'é'.repeat(40)},
  'duplicate page': {allowedPages:['machines','machines']}, 'oversized email': {email:'a'.repeat(255)+'@x.com'},
})) test(`rejects ${label}`, () => assert.throws(() => validateUser({...valid(),...change})));
test('rejects null and arrays', () => { assert.throws(()=>validateUser(null)); assert.throws(()=>validateUser([])); });
test('bounds body without trusting content-length', async () => {
  const req = new Request('https://example.com', {method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({data:'x'.repeat(9000)})});
  await assert.rejects(readBoundedJson(req), /too large/);
});
