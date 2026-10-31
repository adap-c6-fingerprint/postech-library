import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

// Execute inside the development container. No credentials or provider payloads are printed.
const credentials = JSON.parse(readFileSync('/run/secrets/relay.json', 'utf8'));
const configurations = {
  development: ['https://pobook-api-dev.fpmaps.com', 'RELAY_TOKEN'],
  testflight: ['https://pobook-api-testfligh.fpmaps.com', 'RELAY_TOKEN_TESTFLIGHT'],
  production: ['https://pobook-api.fpmaps.com', 'RELAY_TOKEN_PRODUCTION'],
};
const environment = process.env.RELAY_ENVIRONMENT ?? 'development';
assert.ok(Object.hasOwn(configurations, environment), 'Unknown relay environment');
const [base, tokenKey] = configurations[environment];
const RELAY_TOKEN = credentials[tokenKey];
assert.ok(typeof RELAY_TOKEN === 'string' && RELAY_TOKEN.length >= 32, 'Missing relay token');
async function request(path, status, authenticated = true) {
  const response = await fetch(base + path, {
    headers: authenticated ? { Authorization: `Bearer ${RELAY_TOKEN}` } : {},
    redirect: 'manual', signal: AbortSignal.timeout(20000),
  });
  assert.equal(response.status, status, `Unexpected HTTP status at ${path.split('?')[0]}`);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  const text = await response.text();
  for (const value of Object.values(credentials)) assert.ok(!text.includes(value), 'Credential found in response');
  const body = JSON.parse(text);
  console.log(JSON.stringify({ path: path.split('?')[0], status: response.status, cache: response.headers.get('cf-cache-status') }));
  return body;
}
await request('/healthz', 200, false);
await request('/primo/v1/search?q=test', 401, false);
await request('/unknown', 404);
await request('/primo/v1/search?q=test&apikey=client-key', 400);
const primo = await request('/primo/v1/search?q=any%2Ccontains%2C991003794555103286&limit=1', 200);
assert.ok(Array.isArray(primo.docs) && primo.docs.length > 0, 'Primo returned no test record');
const yes24 = await request('/yes24/v1/goods/itemDetail?searchType=ISBN13&query=9788937460777', 200);
assert.ok(yes24.success === true && yes24.data?.items?.some(book => book.isbn13 === '9788937460777'), 'Yes24 test item missing');
const detail = await request('/data4library/api/srchDtlList?isbn13=9788937460777&format=json', 200);
assert.ok(Array.isArray(detail.response?.detail) && detail.response.detail.length > 0, 'Information Naru test detail missing');
const related = await request('/data4library/api/recommandList?isbn13=9788937460777&type=mania&format=json', 200);
assert.ok(Array.isArray(related.response?.docs), 'Information Naru related response missing');
console.log(`${environment} relay smoke checks passed`);
