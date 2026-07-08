import fs from 'node:fs';
import path from 'node:path';

const projectRoot = path.resolve(import.meta.dirname, '..');

function readRequired(relativePath) {
  const filePath = path.join(projectRoot, relativePath);
  if (!fs.existsSync(filePath)) {
    throw new Error(`Missing required file: ${relativePath}`);
  }
  return fs.readFileSync(filePath, 'utf8');
}

function fileExists(relativePath) {
  return fs.existsSync(path.join(projectRoot, relativePath));
}

const indexHtml = readRequired('index.html');
const privacyHtml = readRequired('privacy.html');
const supportHtml = readRequired('support.html');
const manifest = JSON.parse(readRequired('manifest.webmanifest'));
const appStorePlan = readRequired('APPSTORE_SHIP_PLAN_2026-05-11.md');
const lovablePrompt = readRequired('LOVABLE_READY_PROMPT.md');
const photoAttributions = readRequired('PHOTO_ATTRIBUTIONS.md');

const manifestIconPaths = Array.isArray(manifest.icons)
  ? manifest.icons.map((icon) => icon.src.replace(/^\.\//, ''))
  : [];

const checks = [
  {
    id: 'privacy-draft-exists-and-blocks-publication',
    area: 'privacy',
    pass: privacyHtml.includes('Borrador público') &&
      privacyHtml.includes('guarda tu jardín localmente') &&
      privacyHtml.includes('Plant.id/Supabase permanece BLOCKED') &&
      privacyHtml.includes('debe actualizarse para declarar el envío de fotos'),
    evidence: 'Privacy page documents local storage and blocks Plant.id/Supabase/photo-transfer claims until production is real.',
  },
  {
    id: 'support-draft-exists-and-blocks-external-channel',
    area: 'support',
    pass: supportHtml.includes('borrador público') &&
      supportHtml.includes('BLOCKED hasta tener credenciales seguras') &&
      supportHtml.includes('No compres, publiques ni sometas nada sin autorización explícita de Julio'),
    evidence: 'Support page exists and explicitly blocks purchase/submission without Julio authorization.',
  },
  {
    id: 'ios-webapp-metadata-present',
    area: 'iosMetadata',
    pass: indexHtml.includes('apple-mobile-web-app-capable') &&
      indexHtml.includes('apple-mobile-web-app-status-bar-style') &&
      indexHtml.includes('apple-touch-icon') &&
      indexHtml.includes('<link rel="manifest" href="manifest.webmanifest">'),
    evidence: 'Main HTML includes iOS/PWA metadata needed before wrapping or screenshot QA.',
  },
  {
    id: 'manifest-minimum-fields-present',
    area: 'manifest',
    pass: typeof manifest.name === 'string' &&
      typeof manifest.short_name === 'string' &&
      manifest.display === 'standalone' &&
      typeof manifest.start_url === 'string' &&
      typeof manifest.scope === 'string' &&
      manifestIconPaths.length > 0 &&
      manifestIconPaths.every(fileExists),
    evidence: 'Manifest has app identity, standalone display, start/scope, and existing icon files.',
  },
  {
    id: 'appstore-plan-keeps-owner-actions-blocked',
    area: 'appStore',
    pass: appStorePlan.includes('OWNER ACTION ONLY') &&
      appStorePlan.includes('La automatización/cron no debe comprar, someter ni publicar') &&
      appStorePlan.includes('No vender el scanner como reconocimiento real'),
    evidence: 'App Store plan keeps purchase/submission/publishing as owner-only and blocks real-recognition claims.',
  },
  {
    id: 'lovable-prompt-keeps-production-actions-blocked',
    area: 'lovable',
    pass: lovablePrompt.includes('Do not publish, submit to App Store, or connect production credentials') &&
      lovablePrompt.includes('Do not invent botanical claims') &&
      lovablePrompt.includes('Catalog photos have local source/license attribution rows') &&
      lovablePrompt.includes('Privacy/support drafts are local only'),
    evidence: 'Lovable prompt is ready for handoff while preserving no-publish, no-secret, and no-invented-claims constraints.',
  },
];

const blockers = [
  {
    id: 'apple-developer-owner-action',
    blocked: appStorePlan.includes('Julio compra Apple Developer Program si decide avanzar.'),
    evidence: 'Apple Developer enrollment/purchase remains owner-only.',
  },
  {
    id: 'privacy-support-public-url',
    blocked: supportHtml.includes('borrador público hasta que Julio autorice el soporte final para App Store'),
    evidence: 'Privacy/support URLs exist as public drafts, but final App Store support remains owner-authorized.',
  },
  {
    id: 'plantid-supabase-production',
    blocked: privacyHtml.includes('Plant.id/Supabase permanece BLOCKED') &&
      supportHtml.includes('reconocimiento real con Plant.id/Supabase está BLOCKED'),
    evidence: 'Real recognition remains blocked without secure Supabase deploy, secret, and real-photo QA.',
  },
  {
    id: 'appstore-photo-assets',
    blocked: /assets\/flowers\/.+\.jpg.+PENDING/i.test(photoAttributions),
    evidence: 'A catalog photo attribution row still contains a PENDING source or license marker.',
  },
];

const failed = checks.filter((check) => !check.pass);

console.table(checks.map(({ id, area, pass, evidence }) => ({
  id,
  area,
  pass,
  evidence,
})));
console.table(blockers);
console.log(JSON.stringify({
  total: checks.length,
  passed: checks.length - failed.length,
  failed: failed.map((check) => check.id),
  localStaticReadinessReady: failed.length === 0,
  appStoreSubmissionReady: false,
  blockers: blockers.filter((blocker) => blocker.blocked).map((blocker) => blocker.id),
}, null, 2));

if (failed.length) {
  process.exitCode = 1;
}
