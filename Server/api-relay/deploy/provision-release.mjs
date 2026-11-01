import { readFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';

// Pipe into the existing container with node --input-type=module; see README.txt. Never print stdout.
const credentials = JSON.parse(readFileSync('/run/secrets/relay.json', 'utf8'));
if (credentials.RELAY_TOKEN_TESTFLIGHT || credentials.RELAY_TOKEN_PRODUCTION) throw new Error('Release tokens already exist');
credentials.RELAY_TOKEN_TESTFLIGHT = randomBytes(32).toString('hex');
credentials.RELAY_TOKEN_PRODUCTION = randomBytes(32).toString('hex');
process.stdout.write(JSON.stringify(credentials));
