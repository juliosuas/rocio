import { spawnSync } from 'node:child_process';
import path from 'node:path';

const projectRoot = path.resolve(import.meta.dirname, '..');
const auditTimeoutMs = 60_000;
const checks = [
  ['Flower classifier', 'readonly-flower-classifier-harness.mjs', ['--strict']],
  ['Privacy controls', 'privacy-data-controls-audit.mjs', []],
  ['Local calendar-day behavior', 'local-date-key.test.mjs', []],
  ['Photo assets', 'photo-asset-audit.mjs', ['--app-store-ready']],
  ['Commercial claims', 'commercial-claim-audit.mjs', []],
  ['Botanical content', 'botanical-content-audit.mjs', []],
  ['Mobile scanner', 'mobile-scanner-readiness-audit.mjs', []],
  ['Public App Store pages', 'appstore-static-readiness-audit.mjs', []],
  ['Privacy manifest validator', 'privacy-manifest-validation.test.mjs', []],
  ['Native iOS release configuration', 'ios-app-store-readiness-audit.mjs', []],
  ['Supabase Edge runtime', '../supabase/functions/identify-flower/handler.test.ts', []],
  ['Cloud AI security', 'cloud-ai-security-audit.mjs', []],
];

let failures = 0;

for (const [label, script, args] of checks) {
  console.log(`\n=== ${label} ===`);
  const result = spawnSync(process.execPath, [path.join(projectRoot, 'qa', script), ...args], {
    cwd: projectRoot,
    stdio: 'inherit',
    timeout: auditTimeoutMs,
  });

  if (result.status !== 0) {
    failures += 1;
    console.error(`FAILED: ${label}`);
  }
}

console.log(`\nRelease gate: ${checks.length - failures}/${checks.length} checks passed.`);
if (failures) process.exit(1);
