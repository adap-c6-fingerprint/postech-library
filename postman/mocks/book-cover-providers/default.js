// Yes24 상품 상세 계약: https://developers.yes24.com/api-doc/goods-item-detail
// /library/*는 실제 도서관 표지의 403 및 미제공 상황을 재현하는 테스트 전용 경로다.
const http = require('http');
const calls = {};
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jS1sAAAAASUVORK5CYII=', 'base64');
http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const json = (status, body) => {
    res.writeHead(status, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(body));
  };
  if (url.pathname === '/_stats') return json(200, calls);
  if (url.pathname.startsWith('/library/')) {
    const status = Number(url.pathname.split('/').pop());
    res.writeHead(status, { 'Content-Type': 'text/html' });
    return res.end('Library cover unavailable');
  }
  if (url.pathname.startsWith('/goods/')) {
    res.writeHead(200, { 'Content-Type': 'image/png' });
    return res.end(png);
  }
  if (url.pathname !== '/v1/goods/itemDetail') return json(501, { error: 'Endpoint not modeled' });
  if (req.headers['x-api-key'] !== 'proof-key') return json(401, { success: false, errorCode: 'AUTH_001' });
  if (url.searchParams.get('searchType') !== 'ISBN13') return json(400, { success: false, errorCode: 'COMMON_001' });
  const isbn = url.searchParams.get('query');
  calls[isbn] = (calls[isbn] || 0) + 1;
  if (isbn === '9791185042022') return json(404, { success: false, errorCode: 'GOODS_002' });
  if (isbn === '9788931022728' && calls[isbn] === 1) return json(503, { success: false, errorCode: 'UPSTREAM_UNAVAILABLE' });
  const returnedISBN = isbn === '9780131103627' ? '9788966260959' : isbn;
  return json(200, { success: true, errorCode: null, data: { items: [{
    isbn13: returnedISBN,
    cover: isbn === '9788998244545' ? null : 'https://image.yes24.com/goods/372300/L'
  }] } });
}).listen(process.env.PORT || 4174);
