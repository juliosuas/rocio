import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, '..');
const indexHtml = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const launchPlan = fs.readFileSync(path.join(root, 'APP_STORE_LAUNCH_PLAN.md'), 'utf8');

const checks = [
  ['export button exists', indexHtml.includes('id="exportDataBtn"')],
  ['clear button exists', indexHtml.includes('id="clearLocalDataBtn"')],
  ['local data export builder exists', indexHtml.includes('function buildLocalDataExport()')],
  ['download export flow exists', indexHtml.includes('function downloadLocalDataExport()')],
  ['clear local data flow exists', indexHtml.includes('function clearLocalUserData()')],
  ['garden key is centralized', indexHtml.includes("const ROCIO_GARDEN_KEY = 'rocio_garden'")],
  ['scan history key is centralized', indexHtml.includes("const ROCIO_SCAN_HISTORY_KEY = 'rocio_scan_history'")],
  ['demo seeding is one-time', indexHtml.includes("const ROCIO_DEMO_SEEDED_KEY = 'rocio_demo_seeded_v1'") && indexHtml.includes("if (garden.length > 0) {")],
  ['legacy notification key is cleared with user data', indexHtml.includes('safeStorageRemove(rocioLocalStorage, ROCIO_LAST_NOTIFICATION_LEGACY_KEY)')],
  ['local-day notification key is cleared with user data', indexHtml.includes('safeStorageRemove(rocioLocalStorage, ROCIO_LAST_NOTIFICATION_LOCAL_DAY_KEY)')],
  ['garden data is removed explicitly', indexHtml.includes('safeStorageRemove(rocioLocalStorage, ROCIO_GARDEN_KEY)')],
  ['scan history data is removed explicitly', indexHtml.includes('safeStorageRemove(rocioLocalStorage, ROCIO_SCAN_HISTORY_KEY)')],
  ['theme preference is removed explicitly', indexHtml.includes('safeStorageRemove(rocioLocalStorage, ROCIO_THEME_KEY)')],
  ['onboarding preference is removed explicitly', indexHtml.includes('safeStorageRemove(rocioLocalStorage, ROCIO_ONBOARDED_KEY)')],
  ['legacy flower cache is removed explicitly', indexHtml.includes('safeStorageRemove(rocioLocalStorage, ROCIO_FLOWERS_CACHE_KEY)') && indexHtml.includes('safeStorageRemove(rocioLocalStorage, ROCIO_FLOWERS_CACHED_AT_KEY)')],
  ['launch plan tracks export/delete controls', /export a local JSON copy and delete garden data plus scan history/i.test(launchPlan)]
];

let failed = 0;

for (const [label, ok] of checks) {
  console.log(`${ok ? 'PASS' : 'FAIL'} ${label}`);
  if (!ok) failed += 1;
}

if (failed) {
  console.error(`\nPrivacy data controls audit failed: ${failed} check(s).`);
  process.exit(1);
}

console.log('\nPrivacy data controls audit passed.');
