import fs from 'node:fs';
import path from 'node:path';

const projectRoot = path.resolve(import.meta.dirname, '..');
const indexHtml = fs.readFileSync(path.join(projectRoot, 'index.html'), 'utf8');
const readme = fs.readFileSync(path.join(projectRoot, 'README.md'), 'utf8');

const checks = [
  {
    id: 'flower-disease-pending-label',
    area: 'diseaseClaims',
    pass: indexHtml.includes('PENDING botanical review: ${d.treatment}'),
    evidence: 'Flower detail disease treatments render behind PENDING botanical verification.',
  },
  {
    id: 'flower-disease-professional-caveat',
    area: 'diseaseClaims',
    pass: indexHtml.includes('This does not replace a professional diagnosis. Confirm before applying chemicals or removing plants.'),
    evidence: 'Flower detail disease cards include a professional-diagnosis caveat.',
  },
  {
    id: 'symptom-solution-pending-label',
    area: 'doctorClaims',
    pass: indexHtml.includes('PENDING botanical review: ${c.solution}'),
    evidence: 'Doctor symptom solutions render behind PENDING botanical verification.',
  },
  {
    id: 'symptom-solution-caveat',
    area: 'doctorClaims',
    pass: indexHtml.includes('Assistive guidance only. Confirm the diagnosis before applying a treatment.'),
    evidence: 'Doctor symptom cards include an orientation-only caveat.',
  },
  {
    id: 'local-scanner-honest-copy',
    area: 'scannerClaims',
    pass: indexHtml.includes('compare it with the 15 flowers in this demo; the result is assistive.') &&
      indexHtml.includes('Local mode active') &&
      indexHtml.includes('Confirm before adding it to your garden.'),
    evidence: 'Scanner copy labels local matching honestly and asks users to confirm uncertain results.',
  },
  {
    id: 'no-browser-plantid-secret',
    area: 'privacyClaims',
    pass: indexHtml.includes('Plant.id secrets now live in Supabase, never in the browser.') &&
      indexHtml.includes('const ROCIO_SUPABASE_URL = \'\';') &&
      indexHtml.includes('const ROCIO_SUPABASE_PUBLISHABLE_KEY = \'\';'),
    evidence: 'Browser build has no Plant.id secret and Supabase public config is blank.',
  },
  {
    id: 'readme-recognition-claims-honest',
    area: 'scannerClaims',
    pass: readme.includes('`index.html` is a framework-free demo and is not part of the iOS binary.') &&
      readme.includes('The published demo does not create accounts, sync with Supabase, or send images to Plant.id.') &&
      readme.includes('before a reduced copy is sent to Plant.id/Kindwise through Supabase.') &&
      readme.includes('its matching Supabase migrations and Edge Function update have not been deployed.'),
    evidence: 'README separates the local-only web demo from the authenticated native path and names the pending backend deployment.',
  },
];

const failed = checks.filter((check) => !check.pass);

console.table(checks.map(({ id, area, pass, evidence }) => ({
  id,
  area,
  pass,
  evidence,
})));

console.log(JSON.stringify({
  total: checks.length,
  passed: checks.length - failed.length,
  failed: failed.map((check) => check.id),
  appStoreClaimReady: failed.length === 0,
}, null, 2));

if (failed.length) {
  process.exitCode = 1;
}
