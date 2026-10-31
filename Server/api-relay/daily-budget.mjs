import { readFileSync, openSync, writeFileSync, fsyncSync, closeSync, renameSync } from 'node:fs';
import { dirname } from 'node:path';

const providers = ['primo', 'yes24', 'data4library'];

// shortcut: one relay process owns this file; use shared transactional accounting before adding replicas.
export function createDailyBudget(filePath) {
  let state = { version: 1, providers: {} };
  if (filePath) {
    // A missing/corrupt mounted file is an operator error, never an empty quota.
    state = JSON.parse(readFileSync(filePath, 'utf8'));
    if (state.version !== 1 || !state.providers || typeof state.providers !== 'object' || Array.isArray(state.providers)
      || Object.keys(state.providers).some(key => !providers.includes(key))) throw new Error('Invalid quota state');
    for (const entry of Object.values(state.providers)) {
      if (!entry || !Number.isSafeInteger(entry.window) || entry.window < 0
        || !Number.isSafeInteger(entry.count) || entry.count < 0) throw new Error('Invalid quota entry');
    }
  }
  return {
    reserve(provider, timestamp, limit) {
      if (!providers.includes(provider) || !Number.isSafeInteger(timestamp) || timestamp < 0
        || !Number.isSafeInteger(limit) || limit < 1) throw new Error('Invalid quota reservation');
      let entry = state.providers[provider];
      if (!entry || timestamp - entry.window >= 86400000) entry = { window: timestamp, count: 0 };
      if (entry.count >= limit) return false;
      const next = { version: 1, providers: { ...state.providers, [provider]: { ...entry, count: entry.count + 1 } } };
      if (filePath) {
        const temporary = `${filePath}.tmp`;
        const file = openSync(temporary, 'w', 0o600);
        try { writeFileSync(file, JSON.stringify(next)); fsyncSync(file); } finally { closeSync(file); }
        renameSync(temporary, filePath);
        const directory = openSync(dirname(filePath), 'r');
        try { fsyncSync(directory); } finally { closeSync(directory); }
      }
      state = next;
      return true;
    },
  };
}
