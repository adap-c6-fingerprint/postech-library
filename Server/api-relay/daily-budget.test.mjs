import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, readFileSync, rmSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createDailyBudget } from './daily-budget.mjs';

function fixture(t) {
  const directory = mkdtempSync(join(tmpdir(), 'pobook-quota-test-'));
  t.after(() => rmSync(directory, { recursive: true }));
  const path = join(directory, 'quota.json');
  writeFileSync(path, '{"version":1,"providers":{}}');
  return path;
}

test('reservations survive process replacement and expire only after 24 hours', t => {
  const path = fixture(t);
  assert.equal(createDailyBudget(path).reserve('primo', 0, 2), true);
  assert.equal(createDailyBudget(path).reserve('primo', 2000, 2), true);
  assert.equal(createDailyBudget(path).reserve('primo', 4000, 2), false);
  assert.equal(createDailyBudget(path).reserve('yes24', 4000, 1), true);
  assert.equal(createDailyBudget(path).reserve('primo', 86400000, 2), true);
  assert.equal(JSON.parse(readFileSync(path)).providers.primo.count, 1);
});

test('missing, malformed or invalid quota files never become empty quotas', t => {
  const path = fixture(t);
  for (const value of ['invalid', 'null', '{"version":2,"providers":{}}',
    '{"version":1,"providers":{"unknown":{}}}', '{"version":1,"providers":{"primo":{"window":0,"count":-1}}}']) {
    writeFileSync(path, value);
    assert.throws(() => createDailyBudget(path));
  }
  assert.throws(() => createDailyBudget(`${path}.missing`));
});

test('failed durable writes do not authorize a provider request or overwrite the last committed state', t => {
  const path = fixture(t);
  const budget = createDailyBudget(path);
  mkdirSync(`${path}.tmp`);
  assert.throws(() => budget.reserve('primo', 0, 1));
  assert.deepEqual(JSON.parse(readFileSync(path)).providers, {});
});

test('invalid reservations are rejected and clock rollback cannot refresh quota', () => {
  const budget = createDailyBudget();
  assert.equal(budget.reserve('primo', 10000, 1), true);
  assert.equal(budget.reserve('primo', 0, 1), false);
  assert.throws(() => budget.reserve('other', 0, 1));
  assert.throws(() => budget.reserve('primo', 0, 0));
});
