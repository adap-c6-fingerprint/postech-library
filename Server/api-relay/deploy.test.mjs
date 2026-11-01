import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

for (const environment of ['dev', 'release']) {
  for (const failure of ['', 'renew', 'validate', 'reload']) {
    test(`${environment} renewal preserves diagnostics and reports ${failure || 'success'}`, t => {
      const directory = mkdtempSync(join(tmpdir(), 'pobook-renew-'));
      t.after(() => rmSync(directory, { recursive: true, force: true }));
      const log = join(directory, 'renew.log');
      const alert = join(directory, 'alert.log');
      const cron = readFileSync(new URL(`./deploy/pobook-api-${environment}-cert-renew`, import.meta.url), 'utf8');
      // Exercise the exact cron shell payload without Docker, root paths or certificate calls.
      const script = cron.match(/\/bin\/sh -c '(.+)'/)[1]
        .replaceAll('/usr/bin/docker', 'mock_docker')
        .replaceAll('/usr/bin/logger', 'mock_logger')
        .replaceAll('/var/log/pobook-api-cert-renew.log', log);
      const mocks = `
        mock_docker() {
          case "$*" in
            run*) step=renew ;;
            *"nginx -t") step=validate ;;
            *"nginx -s reload") step=reload ;;
            *) return 2 ;;
          esac
          echo "$step diagnostic" >&2
          [ "$step" != "$FAIL_STEP" ]
        }
        mock_logger() { echo "$*" >> "$ALERT_FILE"; }
      `;
      const result = spawnSync('/bin/sh', ['-c', mocks + script], {
        env: { ...process.env, FAIL_STEP: failure, ALERT_FILE: alert }, encoding: 'utf8',
      });
      assert.equal(result.status, failure ? 1 : 0, result.stderr);
      assert.equal(statSync(log).mode & 0o777, 0o600);
      const diagnostics = readFileSync(log, 'utf8');
      assert.ok(diagnostics.includes(`${failure || 'reload'} diagnostic`));
      if (failure) assert.ok(readFileSync(alert, 'utf8').includes(`pobook-api-${environment}-cert-renew`));
      if (failure === 'renew') assert.ok(!diagnostics.includes('validate diagnostic'));
      if (failure === 'validate') assert.ok(!diagnostics.includes('reload diagnostic'));
    });
  }
}
