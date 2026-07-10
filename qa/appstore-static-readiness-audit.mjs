import fs from 'node:fs';
import path from 'node:path';

const projectRoot = path.resolve(import.meta.dirname, '..');

function readRequired(relativePath) {
  const filePath = path.join(projectRoot, relativePath);
  if (!fs.existsSync(filePath)) throw new Error(`Missing required file: ${relativePath}`);
  return fs.readFileSync(filePath, 'utf8');
}

const privacyHtml = readRequired('privacy.html');
const supportHtml = readRequired('support.html');
const manifest = JSON.parse(readRequired('manifest.webmanifest'));
const appStorePlan = readRequired('APP_STORE_LAUNCH_PLAN.md');
const lovablePrompt = readRequired('LOVABLE_READY_PROMPT.md');
const projectFile = readRequired('ios/Rocio.xcodeproj/project.pbxproj');
const internalPublicCopy = /BLOCKED|PENDING|Borrador p[uú]blico|No compres|autorizaci[oó]n expl[ií]cita de Julio|PLANT_ID_API_KEY/i;

const checks = [
  {
    id: 'privacy-page-is-public-safe',
    area: 'privacy',
    pass: privacyHtml.includes('Política de privacidad') &&
      privacyHtml.includes('sincroniza con Supabase') &&
      privacyHtml.includes('Plant.id/Kindwise') &&
      privacyHtml.includes('eliminar permanentemente tu cuenta') &&
      !internalPublicCopy.test(privacyHtml),
    evidence: 'Privacy page discloses account sync, third-party photo processing, and deletion without internal release language.',
  },
  {
    id: 'support-page-is-public-safe',
    area: 'support',
    pass: supportHtml.includes('Centro de soporte') &&
      supportHtml.includes('https://github.com/juliosuas/rocio/issues') &&
      !internalPublicCopy.test(supportHtml),
    evidence: 'Support page provides a real public channel and contains no owner-only instructions.',
  },
  {
    id: 'native-ios-target-present',
    area: 'ios',
    pass: projectFile.includes('PRODUCT_BUNDLE_IDENTIFIER = com.juliosuas.rocio;') &&
      projectFile.includes('productType = "com.apple.product-type.application";'),
    evidence: 'Rocio ships as a native iOS target, not a WebView wrapper.',
  },
  {
    id: 'manifest-minimum-fields-present',
    area: 'pwaFallback',
    pass: manifest.display === 'standalone' && manifest.start_url && manifest.scope &&
      Array.isArray(manifest.icons) && manifest.icons.length > 0,
    evidence: 'The GitHub Pages fallback retains valid installable PWA metadata.',
  },
  {
    id: 'native-launch-plan-current',
    area: 'appStore',
    pass: appStorePlan.includes('SwiftUI') &&
      appStorePlan.includes('com.juliosuas.rocio') &&
      !appStorePlan.includes('Crear proyecto Capacitor'),
    evidence: 'The active launch plan describes the native SwiftUI release.',
  },
  {
    id: 'lovable-contract-is-global-and-honest',
    area: 'lovable',
    pass: lovablePrompt.includes('global flower care app') &&
      lovablePrompt.includes('bilingual English and Spanish') &&
      lovablePrompt.includes('experimental scanner') &&
      !lovablePrompt.includes('Spanish-speaking flower owners'),
    evidence: 'Lovable is aligned with the global bilingual product and honest scanner claim.',
  },
];

const failed = checks.filter((check) => !check.pass);
const hasTeam = [...projectFile.matchAll(/DEVELOPMENT_TEAM = ([^;]*);/g)]
  .some((match) => match[1].trim().replaceAll('"', ''));

console.table(checks);
console.log(JSON.stringify({
  total: checks.length,
  passed: checks.length - failed.length,
  failed: failed.map((check) => check.id),
  localStaticReadinessReady: failed.length === 0,
  appStoreSubmissionReady: failed.length === 0 && hasTeam,
  blockers: hasTeam ? [] : ['apple-developer-team'],
}, null, 2));

if (failed.length) process.exit(1);
