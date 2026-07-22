import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { TextDecoder } from 'node:util';

const root = path.resolve(import.meta.dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const clientExtensions = new Set([
  '.swift', '.plist', '.entitlements', '.xcconfig', '.pbxproj', '.strings', '.xcstrings', '.json',
]);

function clientSourceUnder(relativeDirectory) {
  const directory = path.join(root, relativeDirectory);
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const relativePath = path.join(relativeDirectory, entry.name);
    if (entry.isDirectory()) return clientSourceUnder(relativePath);
    return clientExtensions.has(path.extname(entry.name)) ? [read(relativePath)] : [];
  }).join('\n');
}

function migrationSources() {
  return fs.readdirSync(path.join(root, 'supabase/migrations'))
    .filter((file) => file.endsWith('.sql'))
    .sort()
    .map((file) => ({ file, sql: read(path.join('supabase/migrations', file)) }));
}

const config = read('supabase/config.toml');
const migrations = migrationSources();
const foundationMigrationFile = '20260709000100_rocio_cloud_foundation.sql';
const tombstoneMigrationFile = '20260721000100_preserve_garden_deletions.sql';
const canonicalMigrationFiles = [foundationMigrationFile, tombstoneMigrationFile];
const migrationFiles = migrations.map(({ file }) => file);
const canonicalMigrationHistory =
  JSON.stringify(migrationFiles) === JSON.stringify(canonicalMigrationFiles);
const foundationMigration =
  migrations.find(({ file }) => file === foundationMigrationFile)?.sql ?? '';
const tombstoneMigration =
  migrations.find(({ file }) => file === tombstoneMigrationFile)?.sql ?? '';
const edge = read('supabase/functions/identify-flower/index.ts');
const project = read('ios/Rocio.xcodeproj/project.pbxproj');
const clientSource = `${read('index.html')}\n${clientSourceUnder('ios')}`;
const sharedXcconfig = read('ios/Config/Rocio.xcconfig');
const localXcconfigExample = read('ios/Config/Local.xcconfig.example');
const appInfoPlist = read('ios/Rocio/Resources/Info.plist');
const clientKeyValidatorPath = path.join(root, 'ios', 'Scripts', 'validate-supabase-client-key.sh');
const gitignore = read('.gitignore');
const scanner = read('ios/Rocio/Views/Scanner/ScannerView.swift');
const settings = read('ios/Rocio/Views/Settings/SettingsView.swift');
const rootView = read('ios/Rocio/Views/RootView.swift');
const localizations = read('ios/Rocio/Resources/Localizable.xcstrings');
const privacy = read('APP_STORE_PRIVACY_ANSWERS.md');
const releaseChecklist = read('APP_STORE_RELEASE_CHECKLIST.md');
const appStoreMetadata = read('APP_STORE_METADATA.md');
const publicPrivacy = read('privacy.html');
const policyStatements = foundationMigration.match(/create policy[\s\S]*?;/gi) || [];
const grantStatements = foundationMigration.match(/grant[\s\S]*?;/gi) || [];
const clientSecretPattern = /\b(?:SUPABASE_SERVICE_ROLE_KEY|PLANT_ID_API_KEY)\b|\bsb_secret_[A-Za-z0-9_-]{16,}\b|\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\b/;

const listedFiles = spawnSync(
  'git',
  ['ls-files', '--cached', '--others', '--exclude-standard', '-z'],
  { cwd: root, encoding: 'utf8' },
);
if (listedFiles.error) {
  throw new Error(`Unable to enumerate repository files: ${listedFiles.error.message}`);
}
if (listedFiles.status !== 0) {
  const detail = typeof listedFiles.stderr === 'string' ? listedFiles.stderr.trim() : '';
  throw new Error(`Unable to enumerate repository files${detail ? `: ${detail}` : ` (git exit ${listedFiles.status ?? 'unknown'})`}`);
}

const repositoryFiles = (listedFiles.stdout ?? '').split('\0').filter(Boolean);
const localConfigPath = 'ios/Config/Local.xcconfig';
const textDecoder = new TextDecoder('utf-8', { fatal: true });
const maximumAuditedFileSize = 2 * 1024 * 1024;
const textExtensions = new Set([
  '.css', '.env', '.html', '.js', '.json', '.md', '.mjs', '.pbxproj', '.plist',
  '.py', '.sh', '.sql', '.svg', '.swift', '.toml', '.ts', '.txt', '.webmanifest',
  '.xcconfig', '.xcprivacy', '.xcscheme', '.xcstrings', '.xml', '.yaml', '.yml',
]);
const textBasenames = new Set(['.gitignore', 'Dockerfile', 'Makefile']);

function hasSupabaseCredential(contents) {
  // Current Supabase publishable and secret key formats. Placeholders containing
  // punctuation (for example, <project-key>) intentionally do not match.
  if (/\bsb_(?:publishable|secret)_[A-Za-z0-9_-]{20,}\b/.test(contents)) return true;

  // Legacy anon and service_role keys are JWTs. Decode the payload rather than
  // flagging arbitrary JWT fixtures or merely mentioning the role names.
  const jwtPattern = /\b[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\b/g;
  for (const token of contents.match(jwtPattern) ?? []) {
    try {
      const payload = JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString('utf8'));
      if (payload.role === 'anon' || payload.role === 'service_role') return true;
    } catch {
      // Not a decodable JWT payload, so it is outside this Supabase-key audit.
    }
  }
  return false;
}

const textFiles = repositoryFiles.filter((file) =>
  textBasenames.has(path.basename(file)) ||
    path.basename(file).startsWith('.env') ||
    textExtensions.has(path.extname(file).toLowerCase()),
);
const oversizedTextFiles = textFiles.filter(
  (file) => fs.statSync(path.join(root, file)).size > maximumAuditedFileSize,
);
const credentialFiles = textFiles.filter((file) => {
  const absolutePath = path.join(root, file);
  const metadata = fs.statSync(absolutePath);
  if (!metadata.isFile() || metadata.size > maximumAuditedFileSize) return false;

  const contents = fs.readFileSync(absolutePath);
  if (contents.includes(0)) return false;
  try {
    return hasSupabaseCredential(textDecoder.decode(contents));
  } catch {
    return false;
  }
});

const validateClientKey = (key, buildEnvironment) => spawnSync('/bin/sh', [clientKeyValidatorPath], {
  cwd: root,
  env: { ...process.env, ...buildEnvironment, ROCIO_SUPABASE_PUBLISHABLE_KEY: key },
}).status;
const fakePublishableKey = `sb_publishable_${'q'.repeat(24)}`;
const fakeSecretKey = `sb_secret_${'q'.repeat(24)}`;
const debugBuild = { CONFIGURATION: 'Debug', CODE_SIGNING_ALLOWED: 'YES' };
const unsignedReleaseBuild = { CONFIGURATION: 'Release', CODE_SIGNING_ALLOWED: 'NO' };
const signedReleaseBuild = { CONFIGURATION: 'Release', CODE_SIGNING_ALLOWED: 'YES' };

function identifierUsageIsLimitedTo(contents, identifier, allowedLinePatterns) {
  const lines = contents.split(/\r?\n/).filter((line) => new RegExp(`\\b${identifier}\\b`).test(line));
  return lines.length > 0 && lines.every((line) => allowedLinePatterns.some((pattern) => pattern.test(line)));
}

const serviceRoleKeyUsageIsConstrained = identifierUsageIsLimitedTo(edge, 'serviceRoleKey', [
  /const\s+serviceRoleKey\s*=\s*Deno\.env\.get\("SUPABASE_SERVICE_ROLE_KEY"\)/,
  /createClient\(supabaseUrl,\s*serviceRoleKey\b/,
  /!serviceRoleKey\b/,
]);
const adminClientUsageIsConstrained = identifierUsageIsLimitedTo(edge, 'adminClient', [
  /const\s+adminClient\s*=\s*createClient\(/,
  /adminClient\.from\("scan_results"\)\.insert\(/,
]);

function appBuildConfigurations(contents) {
  const configurations = [];
  const pattern = /^\t\t[A-F0-9]+ \/\* (Debug|Release) \*\/ = \{\n\t\t\tisa = XCBuildConfiguration;([\s\S]*?)^\t\t\};/gm;
  for (const match of contents.matchAll(pattern)) {
    if (/\bPRODUCT_BUNDLE_IDENTIFIER\s*=\s*com\.juliosuas\.rocio\s*;/.test(match[2])) {
      configurations.push({ name: match[1], body: match[2] });
    }
  }
  return configurations;
}

const rocioBuildConfigurations = appBuildConfigurations(project);
const requiredBuildConfigurationNames = ['Debug', 'Release'];
const rocioBuildConfigurationNamed = (name) =>
  rocioBuildConfigurations.find((configuration) => configuration.name === name);

function functionHeader(functionName, source) {
  const escapedName = functionName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const start = source.search(new RegExp(
    `create\\s+(?:or\\s+replace\\s+)?function\\s+${escapedName}\\s*\\(`,
    'i',
  ));
  if (start < 0) return '';
  const definition = source.slice(start);
  const bodyStart = definition.search(/\bas\s+\$(?:[A-Za-z_][A-Za-z0-9_]*)?\$/i);
  return bodyStart < 0 ? '' : definition.slice(0, bodyStart);
}

const requiredSecurityDefinerFunctions = [
  ['public.set_analytics_enabled', foundationMigration],
  ['public.handle_new_user', foundationMigration],
  ['public.consume_scan_quota', foundationMigration],
  ['public.delete_my_account', foundationMigration],
  ['public.reject_stale_garden_update', tombstoneMigration],
  ['public.reject_watering_for_deleted_plant', tombstoneMigration],
  ['public.reset_my_garden', tombstoneMigration],
];
const allSecurityDefinersHaveEmptySearchPath =
  [foundationMigration, tombstoneMigration].every((source) =>
    !/\bsecurity\s+definer\b(?!\s+set\s+search_path\s*=\s*'')/i.test(source));

const oldTombstoneGuard = tombstoneMigration.search(/if\s+old\.deleted_at\s+is\s+not\s+null\s+then/i);
const incomingTombstoneHandler = tombstoneMigration.indexOf(
  'if new.deleted_at is not null then',
  oldTombstoneGuard,
);
const staleActiveUpdateGuard = tombstoneMigration.search(/if\s+new\.updated_at\s*<\s*old\.updated_at\s+then/i);
const tombstoneOrderingIsSafe =
  oldTombstoneGuard >= 0 &&
  incomingTombstoneHandler > oldTombstoneGuard &&
  staleActiveUpdateGuard > incomingTombstoneHandler;
const tombstoneMigrationDoesNotWeakenFoundation =
  !/\b(?:create|alter|drop)\s+policy\b/i.test(tombstoneMigration) &&
  !/\bdisable\s+row\s+level\s+security\b/i.test(tombstoneMigration) &&
  !/\b(?:consume_scan_quota|scan_usage|scan_results|analytics_events)\b/i.test(tombstoneMigration);

const checks = [
  ['canonical-migration-history', canonicalMigrationHistory && foundationMigration.length > 0 && tombstoneMigration.length > 0],
  ['manual-jwt-configured', config.includes('verify_jwt = false') && config.includes('validates it with auth.getUser')],
  ['preflight-allowed', edge.includes('if (req.method === "OPTIONS")')],
  ['row-level-security', foundationMigration.includes('enable row level security') && foundationMigration.includes('auth.uid() = user_id')],
  ['scan-results-no-client-insert-policy',
    !foundationMigration.includes('scan_results_insert_own') &&
    !policyStatements.some((statement) => /on public\.scan_results/i.test(statement) && /for insert/i.test(statement))],
  ['explicit-table-acls',
    foundationMigration.includes('revoke all on table public.scan_results from public, anon, authenticated') &&
    foundationMigration.includes('grant select on table public.scan_results to authenticated') &&
    foundationMigration.includes('grant insert on table public.scan_results to service_role') &&
    foundationMigration.includes('grant select, insert, update, delete on table public.garden_plants to authenticated') &&
    tombstoneMigration.includes('revoke delete on table public.garden_plants from authenticated') &&
    !grantStatements.some((statement) =>
      /insert/i.test(statement) &&
      /on table public\.scan_results/i.test(statement) &&
      /to authenticated/i.test(statement))],
  ['watering-events-same-user-fk',
    foundationMigration.includes('constraint garden_plants_owner_id_unique unique (user_id, id)') &&
    foundationMigration.includes('foreign key (user_id, plant_id)') &&
    foundationMigration.includes('references public.garden_plants(user_id, id)')],
  ['watering-events-reject-tombstones',
    tombstoneMigration.includes('create or replace function public.reject_watering_for_deleted_plant()') &&
    /before\s+insert\s+on\s+public\.watering_events/i.test(tombstoneMigration) &&
    tombstoneMigration.includes('and plants.deleted_at is null') &&
    /for\s+share/i.test(tombstoneMigration) &&
    tombstoneMigration.includes('watering_requires_active_plant') &&
    tombstoneMigration.includes('revoke update on table public.watering_events from authenticated') &&
    tombstoneMigration.includes('revoke delete on table public.watering_events from authenticated')],
  ['atomic-quota', foundationMigration.includes('consume_scan_quota') && foundationMigration.includes("current_plan = 'pro' then 50 else 5")],
  ['plan-not-user-editable', !foundationMigration.includes('profiles_update_own')],
  ['analytics-opt-out-rpc', foundationMigration.includes('set_analytics_enabled(enabled boolean)') && settings.includes('setAnalyticsEnabled(enabled)')],
  ['quota-variable-safe', foundationMigration.includes('current_uid uuid := auth.uid()') && !foundationMigration.includes('current_user uuid :=')],
  ['security-definer-search-path',
    requiredSecurityDefinerFunctions.every(([functionName, source]) => {
      const header = functionHeader(functionName, source);
      return /\bsecurity\s+definer\b/i.test(header) && /\bset\s+search_path\s*=\s*''(?:\s|$)/i.test(header);
    }) && allSecurityDefinersHaveEmptySearchPath],
  ['locale-normalized',
    foundationMigration.includes("pg_catalog.lower(coalesce(new.raw_user_meta_data->>'locale', '')) = 'es'")],
  ['bounded-client-data',
    foundationMigration.includes('garden_plants_nickname_length') &&
    foundationMigration.includes('garden_plants_notes_length') &&
    foundationMigration.includes('analytics_events_properties_size') &&
    foundationMigration.includes('scan_results_confidence_range') &&
    foundationMigration.includes('scan_results_candidate_count_range')],
  ['no-raw-image-column', !foundationMigration.match(/create table[\s\S]*?(image|photo)(_url|_data| bytea)/i)],
  ['garden-deletion-tombstones',
    tombstoneMigration.includes('add column if not exists garden_reset_at timestamptz') &&
    tombstoneMigration.includes('add column if not exists garden_epoch uuid not null default gen_random_uuid()') &&
    tombstoneMigration.includes('add column if not exists deleted_at timestamptz') &&
    tombstoneMigration.includes('add column if not exists garden_epoch uuid') &&
    /before\s+insert\s+or\s+update\s+on\s+public\.garden_plants/i.test(tombstoneMigration) &&
    /current_uid\s+is\s+null\s+or\s+current_uid\s*<>\s*new\.user_id/i.test(tombstoneMigration) &&
    tombstoneMigration.includes('garden_owner_mismatch') &&
    tombstoneMigration.includes('create or replace function public.reset_my_garden(request_id uuid)') &&
    tombstoneMigration.includes('grant execute on function public.reset_my_garden(uuid) to authenticated') &&
    tombstoneOrderingIsSafe],
  ['garden-reset-idempotent-server-epoch',
    tombstoneMigration.includes('create table if not exists public.garden_reset_requests') &&
    tombstoneMigration.includes('primary key (user_id, request_id)') &&
    tombstoneMigration.includes('requests.request_id = reset_my_garden.request_id') &&
    tombstoneMigration.includes('return next_epoch') &&
    tombstoneMigration.includes('new.garden_epoch is distinct from current_epoch') &&
    tombstoneMigration.includes('revoke all on table public.garden_reset_requests from public, anon, authenticated')],
  ['tombstone-migration-preserves-security-boundaries', tombstoneMigrationDoesNotWeakenFoundation],
  ['server-only-secrets-loaded',
    edge.includes('Deno.env.get("PLANT_ID_API_KEY")') &&
    edge.includes('Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")')],
  ['no-client-secret-leakage', !clientSecretPattern.test(clientSource)],
  ['service-role-key-not-leaked', serviceRoleKeyUsageIsConstrained && adminClientUsageIsConstrained],
  ['separate-user-admin-clients',
    edge.includes('createClient(supabaseUrl, anonKey') &&
    edge.includes('createClient(supabaseUrl, serviceRoleKey') &&
    edge.includes('userClient.rpc("consume_scan_quota")') &&
    edge.includes('adminClient.from("scan_results").insert')],
  ['edge-auth-validation',
    edge.includes('authorization?.startsWith("Bearer ")') &&
    edge.includes('userClient.auth.getUser(authorization.slice(7))') &&
    edge.indexOf('authorization?.startsWith("Bearer ")') < edge.indexOf('userClient.auth.getUser(authorization.slice(7))') &&
    edge.indexOf('userClient.auth.getUser(authorization.slice(7))') < edge.indexOf('!serviceRoleKey || !apiKey') &&
    edge.includes('photo_consent_required')],
  ['service-role-fails-closed', edge.includes('!serviceRoleKey') && edge.includes('service_not_configured')],
  ['quota-empty-result-guarded', edge.includes('if (!quota) return json(req, { error: "quota_unavailable" }, 503)')],
  ['client-photo-consent',
    !scanner.includes('@AppStorage("rocio.cloud.photoConsent")') &&
      scanner.includes('photoConsent.begin(image)') &&
      scanner.includes('scanner.consent.continue') &&
      scanner.includes('scanner.consent.on_device') &&
      scanner.includes('destination: .cloud') &&
      scanner.includes('destination: .onDevice')],
  ['account-deletion', foundationMigration.includes('delete_my_account') && settings.includes('Permanently delete account')],
  ['shared-key-default-empty', /^ROCIO_SUPABASE_PUBLISHABLE_KEY =\s*$/m.test(sharedXcconfig)],
  ['optional-local-config', sharedXcconfig.includes('#include? "Local.xcconfig"')],
  ['local-config-ignored', gitignore.split(/\r?\n/).includes(localConfigPath) && !repositoryFiles.includes(localConfigPath)],
  ['example-public-key-only', localXcconfigExample.includes('sb_publishable_<project-key>') && !localXcconfigExample.includes('sb_secret_<')],
  ['debug-release-consume-shared-config',
    requiredBuildConfigurationNames.every((name) => {
      const configuration = rocioBuildConfigurationNamed(name);
      return configuration &&
        /baseConfigurationReference\s*=\s*020000000000000000000040 \/\* Rocio\.xcconfig \*\/;/.test(configuration.body) &&
        /INFOPLIST_FILE\s*=\s*Rocio\/Resources\/Info\.plist;/.test(configuration.body);
    }) &&
      appInfoPlist.includes('<string>$(ROCIO_SUPABASE_PUBLISHABLE_KEY)</string>')],
  ['client-build-rejects-secret-keys',
    project.includes('0C0000000000000000000040 /* Validate Supabase Client Key */') &&
      validateClientKey('', debugBuild) === 0 &&
      validateClientKey('', unsignedReleaseBuild) === 0 &&
      validateClientKey('', signedReleaseBuild) !== 0 &&
      validateClientKey(fakePublishableKey, signedReleaseBuild) === 0 &&
      validateClientKey(fakeSecretKey, signedReleaseBuild) !== 0 &&
      validateClientKey('legacy-service-role-jwt', signedReleaseBuild) !== 0],
  ['project-url-retained', requiredBuildConfigurationNames.every((name) =>
    rocioBuildConfigurationNamed(name)?.body.includes('ROCIO_SUPABASE_URL = "https://gnumzynfewmurvykopxq.supabase.co";'))],
  ['no-supabase-client-key-committed', credentialFiles.length === 0 && oversizedTextFiles.length === 0],
  ['privacy-disclosure', privacy.includes('Plant.id/Kindwise') && privacy.includes('Data Linked To The User')],
  ['per-photo-consent-docs',
    privacy.includes('for every selected photo') &&
      privacy.includes('consent for that photo') &&
      releaseChecklist.includes('consent for each transferred photo') &&
      appStoreMetadata.includes('For every selected scanner photo') &&
      appStoreMetadata.includes('Only the second choice transfers') &&
      publicPrivacy.includes('For every selected photo') &&
      publicPrivacy.includes('consent for that photo') &&
      !privacy.includes('one-time explicit disclosure') &&
      !publicPrivacy.includes('Before the first cloud analysis')],
  ['notification-entrypoint-docs',
    privacy.includes('first-care Garden card or in Settings') &&
      releaseChecklist.includes('explicit tap in Garden or Settings') &&
      appStoreMetadata.includes('first-care card in Garden') &&
      appStoreMetadata.includes('cloud deletion as pending until Rocio confirms synchronization') &&
      !appStoreMetadata.includes('requested only in Settings')],
  ['notification-entrypoint-app-copy',
    rootView.includes('Garden or Settings') &&
      localizations.includes('Garden or Settings') &&
      localizations.includes('Jardín o en Ajustes') &&
      !rootView.includes('only after you enable them in Settings') &&
      !localizations.includes('solo cuando las activas en Ajustes')],
  ['cloud-delete-reminder-copy',
    settings.includes('Garden deleted from this device and Rocio Cloud; local reminders canceled.') &&
      localizations.includes('Jardín eliminado de este dispositivo y de Rocio Cloud; recordatorios locales cancelados.') &&
      !localizations.includes('Jardín y recordatorios eliminados de este dispositivo y Rocio Cloud.')],
];

console.table(checks.map(([id, pass]) => ({ id, pass })));
const failed = checks.filter(([, pass]) => !pass).map(([id]) => id);
if (!canonicalMigrationHistory) {
  console.error(
    `Expected ordered migration history ${canonicalMigrationFiles.join(', ')}, ` +
    `found ${migrationFiles.join(', ') || '(none)'}. Update this source audit when the migration chain changes; ` +
    'the PostgreSQL integration harness remains authoritative for effective state.',
  );
}
if (credentialFiles.length) {
  console.error(`Supabase client/server credential detected in: ${credentialFiles.join(', ')}`);
}
if (oversizedTextFiles.length) {
  console.error(`Text files exceed the credential audit size limit: ${oversizedTextFiles.join(', ')}`);
}
console.log(JSON.stringify({ total: checks.length, passed: checks.length - failed.length, failed }, null, 2));
if (failed.length || credentialFiles.length || oversizedTextFiles.length) process.exitCode = 1;
