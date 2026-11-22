const pages = new Set(['dashboard', 'products', 'stock', 'machines', 'team', 'validation', 'analytics']);
const fields = new Set(['username', 'email', 'fullName', 'password', 'role', 'allowedPages', 'writablePages']);

export function validateUser(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body) ||
      Object.keys(body).some(key => !fields.has(key))) throw new Error('Invalid request');
  const { password, role, allowedPages, writablePages } = body;
  const username = typeof body.username === 'string' ? body.username.trim().toLowerCase() : '';
  const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
  const fullName = typeof body.fullName === 'string' ? body.fullName.trim() : '';
  const validPages = list => Array.isArray(list) && list.length <= pages.size &&
    list.every(page => pages.has(page)) && new Set(list).size === list.length;
  if (!/^[a-z0-9._-]{3,32}$/.test(username) || email.length > 254 ||
      !/^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(email) ||
      !fullName || fullName.length > 120 || /[<>\u0000-\u001f\u007f]/.test(fullName) ||
      !['operator', 'visitor', 'validation'].includes(role) ||
      typeof password !== 'string' || password.length < 12 || password.length > 128 ||
      new TextEncoder().encode(password).length > 72 ||
      !/[a-z]/.test(password) || !/[A-Z]/.test(password) || !/[0-9]/.test(password) ||
      !validPages(allowedPages) || !validPages(writablePages) ||
      writablePages.some(page => !allowedPages.includes(page)) ||
      allowedPages.includes('team') || (role === 'visitor' && writablePages.length > 0)) {
    throw new Error('Invalid user details, password or access rights');
  }
  return { username, email, fullName, password, role, allowedPages, writablePages };
}

export async function readBoundedJson(req, maximum = 8192) {
  if (!req.headers.get('content-type')?.toLowerCase().startsWith('application/json')) {
    throw new Error('JSON required');
  }
  const reader = req.body?.getReader();
  if (!reader) throw new Error('Empty body');
  const chunks = [];
  let length = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    length += value.byteLength;
    if (length > maximum) {
      await reader.cancel();
      throw new Error('Request too large');
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
}
