const http = require('http');
// Public bibliographic samples, observed 2026-10-28. No API credentials.
const documents = [
  {
    "pnx": {
      "control": {
        "sourcerecordid": [
          "991000958759703286"
        ],
        "recordid": [
          "alma991000958759703286"
        ],
        "sourceid": "alma",
        "originalsourceid": [
          "b14710973-82postech_inst"
        ],
        "sourcesystem": [
          "ILS"
        ],
        "sourceformat": [
          "KORMARC"
        ],
        "score": [
          "1.1581758"
        ],
        "isDedup": false
      },
      "display": {
        "title": [
          "사피엔스 "
        ]
      }
    },
    "delivery": {
      "holding": [
        {
          "organization": "82POSTECH_INST",
          "libraryCode": "MAIN",
          "subLocation": "단행본3층",
          "subLocationCode": "c3b",
          "callNumber": "CB113.H4 .H3713 2015",
          "holdId": "2294156640003286",
          "availabilityStatus": "available"
        },
        {
          "organization": "82POSTECH_INST",
          "libraryCode": "MAIN",
          "subLocation": "스마트도서관",
          "subLocationCode": "smart",
          "callNumber": "CB113.H4 .H3713 2015",
          "holdId": "22107952900003286",
          "availabilityStatus": "available"
        },
        {
          "organization": "82POSTECH_INST",
          "libraryCode": "MAIN",
          "subLocation": "삼각서가A2-3: 권장도서100선 (2층)",
          "subLocationCode": "rec100",
          "callNumber": "CB113.H4 .H3713 2015",
          "holdId": "22269461870003286",
          "availabilityStatus": "unavailable"
        }
      ]
    }
  },
  {
    "pnx": {
      "control": {
        "sourcerecordid": [
          "991003794556703286"
        ],
        "recordid": [
          "alma991003794556703286"
        ],
        "sourceid": "alma",
        "originalsourceid": [
          "000017015615"
        ],
        "sourcesystem": [
          "KERIS (KORMARC & MARC21)"
        ],
        "sourceformat": [
          "KORMARC"
        ],
        "score": [
          "0.5291599"
        ],
        "isDedup": false
      },
      "display": {
        "title": [
          "AI 사피엔스 = 전혀 다른 세상의 인류 "
        ]
      }
    },
    "delivery": {
      "holding": [
        {
          "organization": "82POSTECH_INST",
          "libraryCode": "MAIN",
          "subLocation": "단행본3층",
          "subLocationCode": "c3b",
          "callNumber": "HM851 .최73 2024",
          "holdId": "22289661570003286",
          "availabilityStatus": "available"
        }
      ]
    }
  },
  {
    "pnx": {
      "control": {
        "sourcerecordid": [
          "991003550478203286"
        ],
        "recordid": [
          "alma991003550478203286"
        ],
        "sourceid": "alma",
        "originalsourceid": [
          "000015468777"
        ],
        "sourcesystem": [
          "KERIS (KORMARC & MARC21)"
        ],
        "sourceformat": [
          "KORMARC"
        ],
        "score": [
          "0.49805602"
        ],
        "isDedup": false
      },
      "display": {
        "title": [
          "왜 호모 사피엔스만 살아남았을까? "
        ]
      }
    },
    "delivery": {
      "holding": [
        {
          "organization": "82POSTECH_INST",
          "libraryCode": "MAIN",
          "subLocation": "단행본3층",
          "subLocationCode": "c3b",
          "callNumber": "GN470 .이92 2020",
          "holdId": "22226262430003286",
          "availabilityStatus": "available"
        }
      ]
    }
  },
  {
    "pnx": {
      "control": {
        "sourcerecordid": [
          "991003565079503286"
        ],
        "recordid": [
          "alma991003565079503286"
        ],
        "sourceid": "alma",
        "originalsourceid": [
          "000050672253"
        ],
        "sourcesystem": [
          "KERIS (KORMARC & MARC21)"
        ],
        "sourceformat": [
          "KORMARC"
        ],
        "score": [
          "0.3840352"
        ],
        "isDedup": false
      },
      "display": {
        "title": [
          "코로나 사피엔스 : 문명의 대전환, 대한민국 대표 석학 6인이 신인류의 미래를 말한다 "
        ]
      }
    },
    "delivery": {
      "holding": [
        {
          "organization": "82POSTECH_INST",
          "libraryCode": "MAIN",
          "subLocation": "단행본3층",
          "subLocationCode": "c3b",
          "callNumber": "HB3730 .코295 2020",
          "holdId": "22230482870003286",
          "availabilityStatus": "available"
        }
      ]
    }
  },
  {
    "pnx": {
      "control": {
        "sourcerecordid": [
          "991003347372803286"
        ],
        "recordid": [
          "alma991003347372803286"
        ],
        "sourceid": "alma",
        "originalsourceid": [
          "000015047181"
        ],
        "sourcesystem": [
          "KERIS (KORMARC & MARC21)"
        ],
        "sourceformat": [
          "KORMARC"
        ],
        "score": [
          "0.3683647"
        ],
        "isDedup": false
      },
      "display": {
        "title": [
          "먹고 마시는 것들의 자연사 : 맛, 요리, 음식, 사피엔스, 그리고 진화 "
        ]
      }
    },
    "delivery": {
      "holding": [
        {
          "organization": "82POSTECH_INST",
          "libraryCode": "MAIN",
          "subLocation": "단행본3층",
          "subLocationCode": "c3b",
          "callNumber": "GT2855 .S58 2019",
          "holdId": "22156020940003286",
          "availabilityStatus": "available"
        }
      ]
    }
  }
];
const counts = new Map();
const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const send = (status, body, headers = {}) => {
    res.writeHead(status, {'Content-Type': 'application/json', ...headers});
    res.end(JSON.stringify(body));
  };
  if (req.method === 'GET' && url.pathname === '/__counts') return send(200, Object.fromEntries(counts));
  if (req.method !== 'GET' || url.pathname !== '/primo/v1/search') return send(501, {error: 'Not modeled'});
  const query = url.searchParams;
  if (query.get('vid') !== '82POSTECH_INST:82POSTECH' || query.get('tab') !== 'LibraryCatalog'
      || query.get('scope') !== 'MyInstitution' || query.get('skipDelivery') !== 'false') {
    return send(400, {error: 'Invalid Primo query contract'});
  }
  const m = /^any,contains,([0-9]{10,30})$/.exec(query.get('q') || '');
  if (!m) return send(400, {error: 'Invalid MMS query'});
  const id = 'alma' + m[1];
  counts.set(id, (counts.get(id) || 0) + 1);
  if (id === 'alma999999999999990001') return send(503, {error: 'Service unavailable'});
  if (id === 'alma999999999999990002') return send(401, {error: 'Unauthorized'});
  if (id === 'alma999999999999990003') {
    res.writeHead(200, {'Content-Type': 'text/html'}); return res.end('<html>upstream error</html>');
  }
  if (id === 'alma999999999999990004') return send(200, {docs: []});
  if (id === 'alma999999999999990005') return send(200, {docs: [documents[0]]});
  if (id === 'alma999999999999990006') {
    if (counts.get(id) % 2 === 1) return send(429, {error: 'Rate limited'}, {'Retry-After': '0'});
    const doc = JSON.parse(JSON.stringify(documents[0]));
    doc.pnx.control.recordid = [id]; return send(200, {docs: [doc]});
  }
  return send(200, {docs: documents.filter(d => d.pnx.control.recordid.includes(id))});
});
server.listen(process.env.PORT || 47576);
