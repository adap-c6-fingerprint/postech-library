const http = require('http');
// 앱의 기존 중계 경로와 원본 JSON envelope를 재현한다. 실서버의 가용성을 보장하지 않는다.
const counts = {};
http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const json = (status, body) => {
    res.writeHead(status, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(body));
  };
  if (url.pathname === '/__counts') return json(200, counts);
  const paths = ['/yes24/v1/goods/itemDetail', '/data4library/api/srchDtlList', '/data4library/api/recommandList'];
  if (req.method !== 'GET' || !paths.includes(url.pathname)) return json(501, { error: 'Not modeled' });
  if (req.headers.authorization !== 'Bearer local-proof-relay-token-with-at-least-32-characters') {
    return json(401, { error: 'Invalid relay token' });
  }
  if (req.headers['x-api-key'] || [...url.searchParams.keys()].some(key => /^(apikey|authkey)$/i.test(key))) {
    return json(400, { error: 'Provider credential on relay request' });
  }
  counts[url.pathname] = (counts[url.pathname] || 0) + 1;
  if (url.pathname === paths[0]) {
    if (url.searchParams.get('searchType') !== 'ISBN13') return json(400, { error: 'Invalid search type' });
    const isbn = url.searchParams.get('query');
    if (isbn === '9788931022728') return json(503, { success: false, errorCode: 'UPSTREAM_UNAVAILABLE' });
    return json(200, { success: true, errorCode: null, data: { items: [{
      isbn13: isbn, cover: 'https://image.yes24.com/goods/372300/L'
    }] } });
  }
  if (url.searchParams.get('format') !== 'json') return json(400, { error: 'Invalid format' });
  if (url.pathname === paths[1]) {
    return json(200, { response: { detail: [{ book: { bookImageURL: 'https://image.yes24.com/goods/372300/L' } }] } });
  }
  if (url.searchParams.get('type') !== 'mania') return json(400, { error: 'Invalid recommendation type' });
  return json(200, { response: { docs: [] } });
}).listen(process.env.PORT || 47587);
