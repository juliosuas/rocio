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

function allMigrations() {
  return fs.readdirSync(path.join(root, 'supabase/migrations'))
    .filter((file) => file.endsWith('.sql'))
    .sort()
    .map((file) => read(path.join('supabase/migrations', file)))
    .join('\n');
}

const config = read('supabase/config.toml');
const migration = allMigrations();
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
const privacy = read('APP_STORE_PRIVACY_ANSWERS.md');
const policyStatements = migration.match(/create policy[\s\S]*?;/gi) || [];
const grantStatements = migration.match(/grant[\s\S]*?;/gi) || [];
const securityDefinerSettings = migration.match(/security definer set search_path = [^\n]+/gi) || [];
const clientSecretPattern = /\b(?:SUPABASE_SERVICE_ROLE_KEY|PLANT_ID_API_KEY)\b|\bsb_secret_[A-Za-z0-9_-]{16,}\b|\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\b/;
const serviceRoleKeyReferences = edge.match(/\bserviceRoleKey\b/g) || [];
const adminClientReferences = edge.match(/\badminClient\b/g) || [];

const listedFiles = spawnSync(
  'git',
  ['ls-files', '--cached', '--others', '--exclude-standard', '-z'],
  { cwd: root, encoding: 'utf8' },
);
if (listedFiles.status !== 0) {
  throw new Error(`Unable to enumerate repository files: ${listedFiles.stderr.trim()}`);
}

const repositoryFiles = listedFiles.stdout.split('\0').filter(Boolean);
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

const occurrences = (contents, value) => contents.split(value).length - 1;
const validateClientKey = (key) => spawnSync('/bin/sh', [clientKeyValidatorPath], {
  cwd: root,
  env: { ...process.env, ROCIO_SUPABASE_PUBLISHABLE_KEY: key },
}).status;
const fakePublishableKey = `sb_publishable_${'q'.repeat(24)}`;
const fakeSecretKey = `sb_secret_${'q'.repeat(24)}`;

const checks = [
  ['manual-jwt-configured', config.includes('verify_jwt = false') && config.includes('validates it with auth.getUser')],
  ['preflight-allowed', edge.includes('if (req.method === "OPTIONS")')],
  ['row-level-security', migration.includes('enable row level security') && migration.includes('auth.uid() = user_id')],
  ['scan-results-no-client-insert-policy',
    !migration.includes('scan_results_insert_own') &&
    !policyStatements.some((statement) => /on public\.scan_results/i.test(statement) && /for insert/i.test(statement))],
  ['explicit-table-acls',
    migration.includes('revoke all on table public.scan_results from public, anon, authenticated') &&
    migration.includes('grant select on table public.scan_results to authenticated') &&
    migration.includes('grant insert on table public.scan_results to service_role') &&
    !grantStatements.some((statement) =>
      /insert/i.test(statement) &&
      /on table public\.scan_results/i.test(statement) &&
      /to authenticated/i.test(statement))],
  ['watering-events-same-user-fk',
    migration.includes('constraint garden_plants_owner_id_unique unique (user_id, id)') &&
    migration.includes('foreign key (user_id, plant_id)') &&
    migration.includes('references public.garden_plants(user_id, id)')],
  ['atomic-quota', migration.includes('consume_scan_quota') && migration.includes("current_plan = 'pro' then 50 else 5")],
  ['plan-not-user-editable', !migration.includes('profiles_update_own')],
  ['analytics-opt-out-rpc', migration.includes('set_analytics_enabled(enabled boolean)') && settings.includes('setAnalyticsEnabled(enabled)')],
  ['quota-variable-safe', migration.includes('current_uid uuid := auth.uid()') && !migration.includes('current_user uuid :=')],
  ['security-definer-search-path',
    securityDefinerSettings.length === 4 && securityDefinerSettings.every((setting) => setting.endsWith("= ''"))],
  ['locale-normalized',
    migration.includes("pg_catalog.lower(coalesce(new.raw_user_meta_data->>'locale', '')) = 'es'")],
  ['bounded-client-data',
    migration.includes('garden_plants_nickname_length') &&
    migration.includes('garden_plants_notes_length') &&
    migration.includes('analytics_events_properties_size') &&
    migration.includes('scan_results_confidence_range') &&
    migration.includes('scan_results_candidate_count_range')],
  ['no-raw-image-column', !migration.match(/create table[\s\S]*?(image|photo)(_url|_data| bytea)/i)],
  ['server-only-secrets-loaded',
    edge.includes('Deno.env.get("PLANT_ID_API_KEY")') &&
    edge.includes('Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")')],
  ['no-client-secret-leakage', !clientSecretPattern.test(clientSource)],
  ['service-role-key-not-leaked', serviceRoleKeyReferences.length === 3 && adminClientReferences.length === 2],
  ['separate-user-admin-clients',
    edge.includes('createClient(supabaseUrl, anonKey') &&
    edge.includes('createClient(supabaseUrl, serviceRoleKey') &&
    edge.includes('userClient.rpc("consume_scan_quota")') &&
    edge.includes('adminClient.from("scan_results").insert')],
  ['edge-auth-validation',
    edge.includes('authorization?.startsWith("Bearer ")') &&
    edge.includes('userClient.auth.getUser(authorization.slice(7))') &&
    edge.includes('photo_consent_required')],
  ['service-role-fails-closed', edge.includes('!serviceRoleKey') && edge.includes('service_not_configured')],
  ['quota-empty-result-guarded', edge.includes('if (!quota) return json(req, { error: "quota_unavailable" }, 503)')],
  ['client-photo-consent', scanner.includes('rocio.cloud.photoConsent') && scanner.includes('Send this photo')],
  ['account-deletion', migration.includes('delete_my_account') && settings.includes('Permanently delete account')],
  ['shared-key-default-empty', /^ROCIO_SUPABASE_PUBLISHABLE_KEY =\s*$/m.test(sharedXcconfig)],
  ['optional-local-config', sharedXcconfig.includes('#include? "Local.xcconfig"')],
  ['local-config-ignored', gitignore.split(/\r?\n/).includes(localConfigPath) && !repositoryFiles.includes(localConfigPath)],
  ['example-public-key-only', localXcconfigExample.includes('sb_publishable_<project-key>') && !localXcconfigExample.includes('sb_secret_<')],
  ['debug-release-consume-shared-config',
    occurrences(project, 'baseConfigurationReference = 020000000000000000000040 /* Rocio.xcconfig */;') === 2 &&
      occurrences(project, 'INFOPLIST_FILE = Rocio/Resources/Info.plist;') === 2 &&
      appInfoPlist.includes('<string>$(ROCIO_SUPABASE_PUBLISHABLE_KEY)</string>')],
  ['client-build-rejects-secret-keys',
    project.includes('0C0000000000000000000040 /* Validate Supabase Client Key */') &&
      validateClientKey('') === 0 &&
      validateClientKey(fakePublishableKey) === 0 &&
      validateClientKey(fakeSecretKey) !== 0 &&
      validateClientKey('legacy-service-role-jwt') !== 0],
  ['project-url-retained', occurrences(project, 'ROCIO_SUPABASE_URL = "https://gnumzynfewmurvykopxq.supabase.co";') === 2],
  ['no-supabase-client-key-committed', credentialFiles.length === 0 && oversizedTextFiles.length === 0],
  ['privacy-disclosure', privacy.includes('Plant.id/Kindwise') && privacy.includes('Data Linked To The User')],
];

console.table(checks.map(([id, pass]) => ({ id, pass })));
const failed = checks.filter(([, pass]) => !pass).map(([id]) => id);
if (credentialFiles.length) {
  console.error(`Supabase client/server credential detected in: ${credentialFiles.join(', ')}`);
}
if (oversizedTextFiles.length) {
  console.error(`Text files exceed the credential audit size limit: ${oversizedTextFiles.join(', ')}`);
}
console.log(JSON.stringify({ total: checks.length, passed: checks.length - failed.length, failed }, null, 2));
if (failed.length) process.exit(1);
