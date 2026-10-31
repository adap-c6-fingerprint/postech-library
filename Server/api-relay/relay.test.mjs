import { test } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { createRelay, validateCredentials } from './relay.mjs';

const credentials = { RELAY_TOKEN: 'development-token-with-at-least-32-characters', PRIMO_API_KEY: 'primo-secret', YES24_API_KEY: 'yes24-secret', DATA4LIBRARY_API_KEY: 'data4&secret' };
const authorization = `Bearer ${credentials.RELAY_TOKEN}`;
const primoPath = '/primo/v1/search?q=any%2Ccontains%2C과학%20%26%20역사%20OR%20QA1*&offset=50&limit=50&multiFacets=facet_rtype%2Cinclude%2Cprinted_book';
function handler(options = {}) { return createRelay({ credentials, log: () => {}, ...options }); }
function exchange(url, headers = { authorization }, method = 'GET') {
  const req = Object.assign(new EventEmitter(), { url, headers, method });
  const res = Object.assign(new EventEmitter(), { statusCode: 200, destroyed: false, headersSent: false, writableEnded: false,
    writeHead(status, headers) { this.statusCode = status; this.headers = headers; this.headersSent = true; },
    end(body) { this.body = Buffer.from(body ?? ''); this.writableEnded = true; },
  });
  return { req, res };
}
async function call(relay, url, headers, method) {
  const pair = exchange(url, headers, method);
  await relay(pair.req, pair.res);
  return pair.res;
}

test('startup fails closed for missing keys, short tokens and header injection', () => {
  for (const key of Object.keys(credentials)) assert.throws(() => validateCredentials({ ...credentials, [key]: '' }));
  assert.throws(() => validateCredentials({ ...credentials, RELAY_TOKEN: 'short' }));
  assert.throws(() => validateCredentials({ ...credentials, YES24_API_KEY: 'key\r\nInjected: header' }));
});

test('health is public and never calls a provider', async () => {
  const res = await call(handler({ fetchImpl: () => assert.fail('upstream called') }), '/healthz', {});
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.toString(), '{"status":"ok"}');
  assert.equal(res.headers['Cache-Control'], 'no-store');
});

test('wrong or absent bearer tokens never reach upstream', async () => {
  const relay = handler({ fetchImpl: () => assert.fail('upstream called') });
  for (const headers of [{}, { authorization: 'Bearer wrong' }, { authorization: 'apikey primo-secret' }]) {
    assert.equal((await call(relay, primoPath, headers)).statusCode, 401);
  }
});

test('Primo preserves decoded queries, institution, facets and pagination, injects only server key', async () => {
  const relay = handler({ fetchImpl: async (url, options) => {
    assert.equal(url.origin, 'https://api-ap.hosted.exlibrisgroup.com');
    assert.equal(url.searchParams.get('q'), 'any,contains,과학 & 역사 OR QA1*');
    assert.equal(url.searchParams.get('vid'), '82POSTECH_INST:82POSTECH');
    assert.equal(url.searchParams.get('skipDelivery'), 'false');
    assert.equal(url.searchParams.get('offset'), '50');
    assert.equal(url.searchParams.get('limit'), '50');
    assert.equal(url.searchParams.get('multiFacets'), 'facet_rtype,include,printed_book');
    assert.equal(options.headers.Authorization, 'apikey primo-secret');
    assert.equal(options.headers['X-Api-Key'], undefined);
    assert.equal(options.redirect, 'manual');
    return new Response('{"docs":[]}', { headers: { 'Content-Type': 'application/json', 'X-Exl-Api-Remaining': '42', 'Set-Cookie': 'secret' } });
  } });
  const res = await call(relay, primoPath);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.toString(), '{"docs":[]}');
  assert.equal(res.headers['x-exl-api-remaining'], '42');
  assert.equal(res.headers['Set-Cookie'], undefined);
});

for (const [path, provider] of [
  ['/yes24/v1/goods/itemDetail?searchType=ISBN13&query=9788937460777', 'yes24'],
  ['/data4library/api/srchDtlList?isbn13=9788937460777&format=json', 'data4library'],
  ['/data4library/api/recommandList?isbn13=9788937460777&type=mania&format=json', 'data4library'],
]) {
  test(`provider-specific credentials and raw error payload: ${path.split('?')[0]}`, async () => {
    const body = '{"errorCode":"GOODS_001","message":"없음"}';
    const relay = handler({ fetchImpl: async (url, options) => {
      assert.equal(options.headers.Authorization, undefined);
      if (provider === 'yes24') {
        assert.equal(url.origin, 'https://apis.yes24.com');
        assert.equal(options.headers['X-Api-Key'], 'yes24-secret');
        assert.equal(url.searchParams.get('authKey'), null);
      } else {
        assert.equal(url.origin, 'https://data4library.kr');
        assert.equal(url.searchParams.get('authKey'), 'data4&secret');
        assert.equal(options.headers['X-Api-Key'], undefined);
      }
      return new Response(body, { status: 404, headers: { 'Content-Type': 'application/json' } });
    } });
    const res = await call(relay, path);
    assert.equal(res.statusCode, 404);
    assert.equal(res.body.toString(), body);
  });
}

test('only fixed routes and GET are accepted', async () => {
  const relay = handler({ fetchImpl: () => assert.fail('upstream called') });
  assert.equal((await call(relay, '/?url=http://169.254.169.254/')).statusCode, 404);
  assert.equal((await call(relay, '//evil.test/')).statusCode, 400);
  assert.equal((await call(relay, primoPath, undefined, 'POST')).statusCode, 405);
});

test('rejects credential overrides, duplicate/unknown parameters, other institutions and excessive requests', async () => {
  const relay = handler({ fetchImpl: () => assert.fail('upstream called') });
  for (const query of ['q=a&apikey=x', 'q=a&q=b', 'q=a&vid=other', 'q=a&limit=51', 'q=a&offset=1999&limit=2',
    'q=a&multiFacets=facet_rtype,include,other', 'q=%0A', 'q=a&url=https://evil.test', 'q=a&scope=other']) {
    assert.equal((await call(relay, `/primo/v1/search?${query}`)).statusCode, 400, query);
  }
  for (const path of ['/data4library/api/srchDtlList?isbn13=9788937460777&authKey=x',
    '/data4library/api/srchDtlList?isbn13=9788937460777&type=mania',
    '/yes24/v1/goods/itemDetail?query=9788937460777&searchType=ItemId',
    '/yes24/v1/goods/itemDetail?query=not-isbn']) {
    assert.equal((await call(relay, path)).statusCode, 400);
  }
});

test('upstream 429 keeps body and Retry-After, performs no automatic retry', async () => {
  let count = 0;
  const res = await call(handler({ fetchImpl: async () => {
    count++;
    return new Response('quota exceeded', { status: 429, headers: { 'Retry-After': '120' } });
  } }), primoPath);
  assert.equal(res.statusCode, 429);
  assert.equal(res.body.toString(), 'quota exceeded');
  assert.equal(res.headers['retry-after'], '120');
  assert.equal(count, 1);
});

test('redirects are not followed or exposed', async () => {
  const res = await call(handler({ fetchImpl: async () => new Response(null, { status: 302, headers: { Location: 'http://private.test' } }) }), primoPath);
  assert.equal(res.statusCode, 502);
  assert.equal(res.headers.Location, undefined);
});

test('caps response size, handles empty responses and upstream failures', async () => {
  assert.equal((await call(handler({ maxResponseBytes: 3, fetchImpl: async () => new Response('large') }), primoPath)).statusCode, 502);
  const empty = await call(handler({ fetchImpl: async () => new Response(null, { status: 204 }) }), primoPath);
  assert.equal(empty.statusCode, 204);
  assert.equal(empty.body.length, 0);
  const failed = await call(handler({ fetchImpl: async () => { throw new Error('https://provider?apikey=secret'); } }), primoPath);
  assert.equal(failed.statusCode, 502);
  assert.equal(failed.body.toString().includes('secret'), false);
});

test('timeout aborts upstream', async () => {
  const res = await call(handler({ timeoutMs: 5, fetchImpl: async (_, { signal }) => new Promise((_, reject) => {
    signal.addEventListener('abort', () => reject(new Error('aborted')), { once: true });
  }) }), primoPath);
  assert.equal(res.statusCode, 504);
});

test('client disconnect aborts upstream and releases concurrency', async () => {
  let started;
  const ready = new Promise(resolve => { started = resolve; });
  const relay = handler({ fetchImpl: async (_, { signal }) => new Promise((_, reject) => {
    started();
    signal.addEventListener('abort', () => reject(new Error('aborted')), { once: true });
  }) });
  const { req, res } = exchange(primoPath);
  const pending = relay(req, res);
  await ready;
  res.destroyed = true;
  res.emit('close');
  await pending;
  assert.equal(res.headersSent, false);
});

test('daily budget is provider-specific and expires after 24h', async () => {
  let time = 0;
  let count = 0;
  const relay = handler({ now: () => time, dailyLimits: { primo: 1, yes24: 1, data4library: 1 }, fetchImpl: async () => { count++; return new Response('{}'); } });
  assert.equal((await call(relay, primoPath)).statusCode, 200);
  time = 2000;
  assert.equal((await call(relay, primoPath)).statusCode, 429);
  assert.equal(count, 1);
  assert.equal((await call(relay, '/yes24/v1/goods/itemDetail?query=9788937460777')).statusCode, 200);
  time = 86400001;
  assert.equal((await call(relay, primoPath)).statusCode, 200);
});

test('per-second and in-flight limits bound provider load', async () => {
  const fast = handler({ now: () => 0, fetchImpl: async () => new Response('{}') });
  for (let i = 0; i < 5; i++) assert.equal((await call(fast, '/yes24/v1/goods/itemDetail?query=9788937460777')).statusCode, 200);
  assert.equal((await call(fast, '/yes24/v1/goods/itemDetail?query=9788937460777')).statusCode, 429);
  const releases = [];
  const busy = handler({ fetchImpl: async () => new Promise(resolve => releases.push(() => resolve(new Response('{}')))) });
  const first = call(busy, '/yes24/v1/goods/itemDetail?query=9788937460777');
  const second = call(busy, '/yes24/v1/goods/itemDetail?query=9788937460777');
  assert.equal((await call(busy, '/yes24/v1/goods/itemDetail?query=9788937460777')).statusCode, 429);
  releases.forEach(release => release());
  await Promise.all([first, second]);
});

test('logs only timing, status and provider', async () => {
  const logs = [];
  await call(handler({ log: line => logs.push(JSON.parse(line)), fetchImpl: async () => new Response('{}') }), primoPath);
  assert.deepEqual(Object.keys(logs[0]).sort(), ['durationMs', 'provider', 'status']);
  assert.equal(JSON.stringify(logs).includes('secret'), false);
});
