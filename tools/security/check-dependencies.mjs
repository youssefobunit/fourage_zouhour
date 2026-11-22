import { readFileSync } from 'node:fs';

// Query exact locked versions, including transitive packages. Never send code,
// environment variables, tokens or project configuration to the advisory API.
const lock = readFileSync('pubspec.lock', 'utf8');
const packages = [...lock.matchAll(/^  ([\w]+):\r?\n([\s\S]*?)(?=^  \w+:|^sdks:|$(?![\s\S]))/gm)]
  .filter(([, , body]) => /source: hosted/.test(body))
  .map(([, name, body]) => ({ package: { name, ecosystem: 'Pub' }, version: body.match(/version: "([^"]+)"/)[1] }));
const response = await fetch('https://api.osv.dev/v1/querybatch', {
  method: 'POST', headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ queries: packages }), signal: AbortSignal.timeout(30000),
});
if (!response.ok) throw new Error(`Advisory service failed: ${response.status}`);
const data = await response.json();
if (!Array.isArray(data.results) || data.results.length !== packages.length) throw new Error('Incomplete advisory response');
let count = 0;
data.results.forEach((result, i) => {
  for (const advisory of result.vulns ?? []) {
    console.log(`${packages[i].package.name}@${packages[i].version}: ${advisory.id}`);
    count++;
  }
});
console.log(`Checked ${packages.length} locked Pub packages; ${count} advisory matches.`);
process.exitCode = count ? 1 : 0;
