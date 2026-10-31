import { readFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import { validateCredentials } from '../relay.mjs';

// Pipe stdout directly into the remote private file; never run this to a terminal or a log.
const source = readFileSync(process.argv[2], 'utf8');
const credentials = { RELAY_TOKEN: randomBytes(32).toString('hex') };
for (const key of ['PRIMO_API_KEY', 'YES24_API_KEY', 'DATA4LIBRARY_API_KEY']) {
  const line = source.match(new RegExp(`^\\s*${key}\\s*=\\s*(.*)$`, 'm'))?.[1]?.trim();
  if (!line || !/^[A-Za-z0-9._-]+$/.test(line)) throw new Error(`Missing or unsupported credential: ${key}`);
  credentials[key] = line;
}
validateCredentials(credentials);
process.stdout.write(JSON.stringify(credentials));
