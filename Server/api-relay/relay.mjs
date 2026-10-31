import { timingSafeEqual } from 'node:crypto';

const routes = new Map([
  ['/primo/v1/search', { provider: 'primo', url: 'https://api-ap.hosted.exlibrisgroup.com/primo/v1/search' }],
  ['/yes24/v1/goods/itemDetail', { provider: 'yes24', url: 'https://apis.yes24.com/v1/goods/itemDetail' }],
  ['/data4library/api/srchDtlList', { provider: 'data4library', url: 'https://data4library.kr/api/srchDtlList' }],
  ['/data4library/api/recommandList', { provider: 'data4library', url: 'https://data4library.kr/api/recommandList' }],
]);
const providerKeys = { primo: 'PRIMO_API_KEY', yes24: 'YES24_API_KEY', data4library: 'DATA4LIBRARY_API_KEY' };
const perSecond = { primo: 10, yes24: 5, data4library: 10 };
const concurrent = { primo: 4, yes24: 2, data4library: 10 };
export const defaultDailyLimits = { primo: 1500, yes24: 1000, data4library: 400 };

export function validateCredentials(credentials) {
  for (const key of ['RELAY_TOKEN', ...Object.values(providerKeys)]) {
    if (typeof credentials[key] !== 'string' || !credentials[key].trim() || /[\r\n]/.test(credentials[key])) {
      throw new Error(`Missing or invalid credential: ${key}`);
    }
  }
  if (credentials.RELAY_TOKEN.length < 32) throw new Error('RELAY_TOKEN must have at least 32 characters');
}

function integer(value, min, max) {
  return /^(0|[1-9]\d*)$/.test(value) && Number(value) >= min && Number(value) <= max;
}

function upstreamURL(input, route) {
  const params = input.searchParams;
  const allowed = route.provider === 'primo'
    ? ['vid', 'tab', 'scope', 'q', 'multiFacets', 'lang', 'offset', 'limit', 'skipDelivery']
    : route.provider === 'yes24' ? ['searchType', 'query'] : ['isbn13', 'type', 'format'];
  for (const key of params.keys()) {
    if (!allowed.includes(key) || params.getAll(key).length !== 1) throw new Error('Invalid query');
  }
  const output = new URL(route.url);
  if (route.provider === 'primo') {
    const fixed = { vid: '82POSTECH_INST:82POSTECH', tab: 'LibraryCatalog', scope: 'MyInstitution', lang: 'ko', skipDelivery: 'false' };
    for (const [key, value] of Object.entries(fixed)) {
      if (params.has(key) && params.get(key) !== value) throw new Error('Invalid scope');
      output.searchParams.set(key, value);
    }
    const query = params.get('q');
    if (!query || query.length > 12000 || /[\x00-\x1f\x7f]/.test(query)) throw new Error('Invalid search');
    const offset = params.get('offset') ?? '0';
    const limit = params.get('limit') ?? '20';
    if (!integer(offset, 0, 1999) || !integer(limit, 1, 50) || Number(offset) + Number(limit) > 2000) throw new Error('Invalid page');
    output.searchParams.set('q', query);
    output.searchParams.set('offset', offset);
    output.searchParams.set('limit', limit);
    if (params.has('multiFacets')) {
      const facets = params.get('multiFacets').split('|,|');
      if (facets.length > 3 || facets.some(value => !/^facet_rtype,include,(books|printed_book|journals)$/.test(value))) throw new Error('Invalid facets');
      output.searchParams.set('multiFacets', facets.join('|,|'));
    }
  } else {
    const isbn = params.get(route.provider === 'yes24' ? 'query' : 'isbn13');
    if (!/^97[89]\d{10}$/.test(isbn ?? '')) throw new Error('Invalid ISBN13');
    if (route.provider === 'yes24') {
      if (params.has('searchType') && params.get('searchType') !== 'ISBN13') throw new Error('Invalid search type');
      output.searchParams.set('searchType', 'ISBN13');
      output.searchParams.set('query', isbn);
    } else {
      if (params.has('format') && params.get('format') !== 'json') throw new Error('Invalid format');
      const related = input.pathname.endsWith('/recommandList');
      if (params.has('type') && (!related || params.get('type') !== 'mania')) throw new Error('Invalid related type');
      output.searchParams.set('isbn13', isbn);
      output.searchParams.set('format', 'json');
      if (related) output.searchParams.set('type', 'mania');
    }
  }
  return output;
}

// shortcut: dev-only counters reset on restart and are not shared across replicas; use shared accounting before production.
export function createRelay({ credentials, fetchImpl = fetch, now = Date.now, dailyLimits = defaultDailyLimits,
  timeoutMs = 12000, maxResponseBytes = 4 * 1024 * 1024, log = console.info }) {
  validateCredentials(credentials);
  for (const provider of Object.keys(providerKeys)) {
    if (!Number.isSafeInteger(dailyLimits[provider]) || dailyLimits[provider] < 1) throw new Error('Invalid daily limit');
  }
  const token = Buffer.from(`Bearer ${credentials.RELAY_TOKEN}`);
  const counters = new Map();
  function error(res, status, code) {
    res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store',
      ...(status === 429 ? { 'Retry-After': '60' } : {}) });
    res.end(JSON.stringify({ error: code }));
  }
  return async (req, res) => {
    const started = now();
    let route;
    let counter;
    let timer;
    let controller;
    const disconnected = () => { if (!res.writableEnded) controller?.abort(); };
    try {
      if (req.method !== 'GET') return error(res, 405, 'method_not_allowed');
      if (!req.url?.startsWith('/') || req.url.startsWith('//') || req.url.length > 16000) return error(res, 400, 'invalid_request');
      const input = new URL(req.url, 'http://relay.invalid');
      if (input.pathname === '/healthz' && !input.search) {
        res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
        return res.end('{"status":"ok"}');
      }
      const received = Buffer.from(req.headers.authorization ?? '');
      if (received.length !== token.length || !timingSafeEqual(received, token)) return error(res, 401, 'unauthorized');
      route = routes.get(input.pathname);
      if (!route) return error(res, 404, 'route_not_found');
      let target;
      try { target = upstreamURL(input, route); } catch { return error(res, 400, 'invalid_query'); }
      const provider = route.provider;
      const timestamp = now();
      const second = Math.floor(timestamp / 1000);
      counter = counters.get(provider);
      if (!counter) {
        counter = { active: 0, second, count: 0, window: timestamp, daily: 0 };
        counters.set(provider, counter);
      }
      if (timestamp - counter.window >= 86400000) { counter.window = timestamp; counter.daily = 0; }
      if (counter.second !== second) { counter.second = second; counter.count = 0; }
      if (counter.active >= concurrent[provider] || counter.count >= perSecond[provider] || counter.daily >= dailyLimits[provider]) {
        counter = undefined;
        return error(res, 429, 'relay_limit');
      }
      counter.active++;
      counter.count++;
      counter.daily++;
      // Information Naru returns 406 for Accept: application/json even with format=json.
      const headers = { Accept: provider === 'primo' ? 'application/json' : '*/*' };
      if (provider === 'primo') headers.Authorization = `apikey ${credentials.PRIMO_API_KEY}`;
      else if (provider === 'yes24') headers['X-Api-Key'] = credentials.YES24_API_KEY;
      else target.searchParams.set('authKey', credentials.DATA4LIBRARY_API_KEY);
      controller = new AbortController();
      req.on('aborted', disconnected);
      res.on('close', disconnected);
      timer = setTimeout(() => controller.abort(), timeoutMs);
      const upstream = await fetchImpl(target, { method: 'GET', headers, redirect: 'manual', signal: controller.signal });
      if (upstream.status >= 300 && upstream.status < 400) {
        await upstream.body?.cancel();
        return error(res, 502, 'upstream_redirect');
      }
      const chunks = [];
      let size = 0;
      for await (const chunk of upstream.body ?? []) {
        size += chunk.length;
        if (size > maxResponseBytes) { controller.abort(); return error(res, 502, 'upstream_too_large'); }
        chunks.push(Buffer.from(chunk));
      }
      if (res.destroyed) return;
      const responseHeaders = { 'Content-Type': upstream.headers.get('content-type') ?? 'application/json', 'Cache-Control': 'no-store' };
      for (const name of ['retry-after', 'x-exl-api-remaining']) {
        if (upstream.headers.has(name)) responseHeaders[name] = upstream.headers.get(name);
      }
      res.writeHead(upstream.status, responseHeaders);
      res.end(Buffer.concat(chunks));
    } catch {
      if (!res.destroyed && !res.headersSent) error(res,  controller?.signal.aborted ? 504 : 502, controller?.signal.aborted ? 'upstream_timeout' : 'upstream_unavailable');
    } finally {
      clearTimeout(timer);
      req.off('aborted', disconnected);
      res.off('close', disconnected);
      if (counter) counter.active--;
      // Never log queries, client addresses, credentials, upstream URLs or response bodies.
      log(JSON.stringify({ provider: route?.provider ?? 'none', status: res.statusCode, durationMs: now() - started }));
    }
  };
}
