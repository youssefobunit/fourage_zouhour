import { execFileSync } from 'node:child_process';
import { readFileSync, statSync } from 'node:fs';

// Inspect tracked and new, non-ignored files. Never print matching credentials.
const files = [...new Set(execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard', '-z'],
  {encoding:'utf8'}).split('\0').filter(Boolean))];
let issues=0;
for (const file of files) {
  if (/(?:^|\/)\.env(?:\.|$)/.test(file) && !file.endsWith('.example') ||
      /\.(jks|keystore|p12|pfx|pem)$/.test(file) || /(?:key|signing)\.properties$/.test(file)) {
    console.log(`Private material must not be committed: ${file}`); issues++; continue;
  }
  if (!/\.(dart|ts|mjs|js|sql|json|ya?ml|toml|properties|md|txt)$/.test(file)) continue;
  let source;
  try { if (statSync(file).size > 2000000) continue; source=readFileSync(file,'utf8'); }
  catch { continue; } // Deleted tracked file.
  let found = /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/.test(source) ||
    /\bsb_secret_[A-Za-z0-9_-]{24,}/.test(source) ||
    /\bgh[pousr]_[A-Za-z0-9]{30,}/.test(source) || /\bgithub_pat_[A-Za-z0-9_]{60,}/.test(source);
  for (const token of source.matchAll(/\beyJ[A-Za-z0-9_-]+\.([A-Za-z0-9_-]+)\.[A-Za-z0-9_-]+/g)) {
    try { if (JSON.parse(Buffer.from(token[1],'base64url').toString()).role==='service_role') found=true; }
    catch { /* Not a JWT. */ }
  }
  if (found) { console.log(`Possible secret in ${file} (value hidden)`); issues++; }
}
console.log(`Checked ${files.length} repository files; ${issues} credential findings.`);
process.exitCode=issues ? 1 : 0;
