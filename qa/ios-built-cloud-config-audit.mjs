import fs from 'node:fs';
import { spawnSync } from 'node:child_process';

const infoPlistPath = process.argv[2];
if (!infoPlistPath || !fs.existsSync(infoPlistPath)) {
  console.error('Usage: node qa/ios-built-cloud-config-audit.mjs <built-app-Info.plist>');
  process.exit(2);
}

const converted = spawnSync(
  'plutil',
  ['-convert', 'json', '-o', '-', infoPlistPath],
  { encoding: 'utf8' },
);
if (converted.status !== 0) {
  console.error(converted.stderr.trim());
  process.exit(2);
}

const info = JSON.parse(converted.stdout);
const checks = [
  ['project URL is bundled', info.ROCIOSupabaseURL === 'https://gnumzynfewmurvykopxq.supabase.co'],
  ['public key entry exists', Object.hasOwn(info, 'ROCIOSupabaseAnonKey')],
  ['clean CI build is intentionally unconfigured', info.ROCIOSupabaseAnonKey === ''],
  ['no unresolved build setting', !JSON.stringify(info).includes('$(')],
];

for (const [name, passed] of checks) {
  console.log(`${passed ? 'PASS' : 'FAIL'} ${name}`);
}
const failed = checks.filter(([, passed]) => !passed).map(([name]) => name);
console.log(JSON.stringify({ infoPlistPath, failed }, null, 2));
if (failed.length) process.exit(1);
