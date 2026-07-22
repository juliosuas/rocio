import fs from 'node:fs';
import path from 'node:path';

const projectRoot = path.resolve(import.meta.dirname, '..');
const indexHtml = fs.readFileSync(path.join(projectRoot, 'index.html'), 'utf8');
const readme = fs.readFileSync(path.join(projectRoot, 'README.md'), 'utf8');

const checks = [
  {
    id: 'flower-disease-pending-label',
    area: 'diseaseClaims',
    pass: indexHtml.includes('PENDING verificación botánica: ${d.treatment}'),
    evidence: 'Flower detail disease treatments render behind PENDING botanical verification.',
  },
  {
    id: 'flower-disease-professional-caveat',
    area: 'diseaseClaims',
    pass: indexHtml.includes('No sustituye diagnóstico profesional; confirma antes de aplicar químicos o retirar plantas.'),
    evidence: 'Flower detail disease cards include a professional-diagnosis caveat.',
  },
  {
    id: 'symptom-solution-pending-label',
    area: 'doctorClaims',
    pass: indexHtml.includes('PENDING verificación botánica: ${c.solution}'),
    evidence: 'Doctor symptom solutions render behind PENDING botanical verification.',
  },
  {
    id: 'symptom-solution-caveat',
    area: 'doctorClaims',
    pass: indexHtml.includes('Guía orientativa; confirma el diagnóstico antes de aplicar tratamientos.'),
    evidence: 'Doctor symptom cards include an orientation-only caveat.',
  },
  {
    id: 'local-scanner-honest-copy',
    area: 'scannerClaims',
    pass: indexHtml.includes('comparará con las 15 flores de esta demo; el resultado es orientativo.') &&
      indexHtml.includes('Modo local activo') &&
      indexHtml.includes('Confirma antes de agregarla a tu jardín.'),
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
    pass: readme.includes('`index.html` es una demo sin framework y no forma parte del binario iOS.') &&
      readme.includes('La versión publicada no crea cuentas, no sincroniza con Supabase y no envía imágenes a Plant.id.') &&
      readme.includes('antes de enviar una copia reducida a Plant.id/Kindwise mediante Supabase.') &&
      readme.includes('aún no se despliega al proyecto remoto.'),
    evidence: 'README separates the local-only web demo from the authenticated native path and names the pending remote migration.',
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
