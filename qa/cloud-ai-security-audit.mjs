import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const config = read('supabase/config.toml');
const migration = read('supabase/migrations/20260709000100_rocio_cloud_foundation.sql');
const edge = read('supabase/functions/identify-flower/index.ts');
const project = read('ios/Rocio.xcodeproj/project.pbxproj');
const scanner = read('ios/Rocio/Views/Scanner/ScannerView.swift');
const settings = read('ios/Rocio/Views/Settings/SettingsView.swift');
const privacy = read('APP_STORE_PRIVACY_ANSWERS.md');

const checks = [
  ['jwt-required', config.includes('verify_jwt = true')],
  ['row-level-security', migration.includes('enable row level security') && migration.includes('auth.uid() = user_id')],
  ['atomic-quota', migration.includes('consume_scan_quota') && migration.includes("current_plan = 'pro' then 50 else 5")],
  ['plan-not-user-editable', !migration.includes('profiles_update_own')],
  ['analytics-opt-out-rpc', migration.includes('set_analytics_enabled(enabled boolean)') && settings.includes('setAnalyticsEnabled(enabled)')],
  ['quota-variable-safe', migration.includes('current_uid uuid := auth.uid()') && !migration.includes('current_user uuid :=')],
  ['no-raw-image-column', !migration.match(/create table[\s\S]*?(image|photo)(_url|_data| bytea)/i)],
  ['server-side-provider-key', edge.includes('Deno.env.get("PLANT_ID_API_KEY")') && !project.includes('PLANT_ID_API_KEY')],
  ['edge-auth-validation', edge.includes('client.auth.getUser') && edge.includes('photo_consent_required')],
  ['quota-empty-result-guarded', edge.includes('if (!quota) return json(req, { error: "quota_unavailable" }, 503)')],
  ['client-photo-consent', scanner.includes('rocio.cloud.photoConsent') && scanner.includes('Send this photo')],
  ['account-deletion', migration.includes('delete_my_account') && settings.includes('Permanently delete account')],
  ['release-key-not-committed', project.includes('ROCIO_SUPABASE_ANON_KEY = "";')],
  ['privacy-disclosure', privacy.includes('Plant.id/Kindwise') && privacy.includes('Data Linked To The User')],
];

console.table(checks.map(([id, pass]) => ({ id, pass })));
const failed = checks.filter(([, pass]) => !pass).map(([id]) => id);
console.log(JSON.stringify({ total: checks.length, passed: checks.length - failed.length, failed }, null, 2));
if (failed.length) process.exit(1);
