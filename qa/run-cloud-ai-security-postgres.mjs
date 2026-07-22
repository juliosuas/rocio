import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const root = path.resolve(import.meta.dirname, '..');
const databaseURL = process.env.ROCIO_SECURITY_DATABASE_URL;

if (!databaseURL) {
  console.error(
    'Set ROCIO_SECURITY_DATABASE_URL to a disposable local PostgreSQL 16 database. ' +
    'The harness runs all migrations in one transaction and rolls it back.',
  );
  process.exit(2);
}

let parsedURL;
try {
  parsedURL = new URL(databaseURL);
} catch {
  console.error('ROCIO_SECURITY_DATABASE_URL is not a valid PostgreSQL URL.');
  process.exit(2);
}

const localHosts = new Set(['', 'localhost', '127.0.0.1', '[::1]']);
if (!['postgres:', 'postgresql:'].includes(parsedURL.protocol) || !localHosts.has(parsedURL.hostname)) {
  console.error('Refusing to run migration QA against a non-local PostgreSQL server.');
  process.exit(2);
}

const migrationsDirectory = path.join(root, 'supabase', 'migrations');
const migrations = fs.readdirSync(migrationsDirectory)
  .filter((file) => file.endsWith('.sql'))
  .sort();

if (!migrations.length) {
  console.error('No Supabase migrations found.');
  process.exit(1);
}

const invalidNames = migrations.filter((file) => !/^\d{14}_[a-z0-9_]+\.sql$/.test(file));
const versions = migrations.map((file) => file.slice(0, 14));
const duplicateVersions = versions.filter((version, index) => versions.indexOf(version) !== index);
if (invalidNames.length || duplicateVersions.length) {
  if (invalidNames.length) console.error(`Invalid migration filenames: ${invalidNames.join(', ')}`);
  if (duplicateVersions.length) console.error(`Duplicate migration versions: ${[...new Set(duplicateVersions)].join(', ')}`);
  process.exit(1);
}

const foundationMigration = '20260709000100_rocio_cloud_foundation.sql';
const upgradeFixture = path.join(root, 'qa', 'cloud-ai-security-postgres-upgrade-fixture.sql');
const migrationFiles = migrations.flatMap((file) => {
  const migration = path.join(migrationsDirectory, file);
  return file === foundationMigration ? [migration, upgradeFixture] : [migration];
});
const files = [
  path.join(root, 'qa', 'cloud-ai-security-postgres-bootstrap.sql'),
  ...migrationFiles,
  path.join(root, 'qa', 'cloud-ai-security-postgres.test.sql'),
];
const args = [
  '--no-psqlrc',
  '--set', 'ON_ERROR_STOP=1',
  '--dbname', databaseURL,
  ...files.flatMap((file) => ['--file', file]),
];

console.log(`Applying ${migrations.length} ordered migration(s) to disposable PostgreSQL QA.`);
for (const migration of migrations) console.log(`- ${migration}`);

const result = spawnSync('psql', args, {
  cwd: root,
  stdio: 'inherit',
  timeout: 60_000,
});

if (result.error) {
  console.error(`Unable to run psql: ${result.error.message}`);
  process.exit(1);
}
if (result.status !== 0) {
  console.error(`PostgreSQL migration QA failed with exit ${result.status ?? 'unknown'}.`);
  process.exit(1);
}

console.log(`PostgreSQL migration QA passed for ${migrations.length} migration(s).`);
