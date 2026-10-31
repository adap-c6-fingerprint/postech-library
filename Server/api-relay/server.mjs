import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { createRelay, defaultDailyLimits } from './relay.mjs';

let credentials;
try { credentials = JSON.parse(readFileSync('/run/secrets/relay.json', 'utf8')); }
catch { throw new Error('Cannot read valid relay credentials'); }
const dailyLimits = Object.fromEntries(Object.keys(defaultDailyLimits).map(provider => [provider,
  Number(process.env[`${provider.toUpperCase()}_DAILY_LIMIT`] ?? defaultDailyLimits[provider]) ]));
const server = createServer({ maxHeaderSize: 20000 }, createRelay({ credentials, dailyLimits }));
server.headersTimeout = 10000;
server.requestTimeout = 15000;
server.keepAliveTimeout = 5000;
server.maxConnections = 100;
server.listen(3000, '0.0.0.0');
process.on('SIGTERM', () => {
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 15000).unref();
});
