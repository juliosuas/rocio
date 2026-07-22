import fs from 'node:fs';
import path from 'node:path';

const projectRoot = path.resolve(import.meta.dirname, '..');
const indexHtml = fs.readFileSync(path.join(projectRoot, 'index.html'), 'utf8');

function cssRule(selector) {
  const escaped = selector.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = indexHtml.match(new RegExp(`${escaped}\\s*\\{(?<body>[\\s\\S]*?)\\n\\}`, 'm'));
  return match?.groups?.body ?? '';
}

function pxValue(ruleBody, property) {
  const escaped = property.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = ruleBody.match(new RegExp(`${escaped}\\s*:\\s*([0-9.]+)px`));
  return match ? Number(match[1]) : null;
}

function includesAll(source, phrases) {
  return phrases.every((phrase) => source.includes(phrase));
}

const fabRule = cssRule('.scanner-fab');
const closeRule = cssRule('.scanner-close');
const captureRule = cssRule('.scanner-capture-btn');
const uploadButtonRule = cssRule('.scanner-upload-btn');
const resultRule = cssRule('.scanner-result');
const careGridRule = cssRule('.scanner-result-care');

const checks = [
  {
    id: 'scanner-entrypoints-present',
    area: 'mobileScanner',
    pass: includesAll(indexHtml, [
      'id="scannerFab"',
      'id="scannerOverlay"',
      'id="scannerCaptureBtn"',
      'id="scannerUploadBtn"',
      'id="scannerPermUploadBtn"',
      'id="scannerResult"',
    ]),
    evidence: 'Scanner has FAB, overlay, capture, upload fallback, permission fallback, and result sheet entrypoints.',
  },
  {
    id: 'scanner-honest-local-copy',
    area: 'recognitionClaims',
    pass: includesAll(indexHtml, [
      'compare it with the 15 flowers in this demo; the result is assistive.',
      'Local mode active',
      'The result is uncertain',
      'Confirm before adding it to your garden',
    ]),
    evidence: 'Mobile scanner copy keeps local recognition framed as uncertain matching, not real botanical recognition.',
  },
  {
    id: 'scanner-no-clear-flower-fallback',
    area: 'recognitionClaims',
    pass: includesAll(indexHtml, [
      'No clear flower detected',
      'Foliage or background dominates the frame',
      'Foliage or background dominates, not a flower',
      'Center one open flower to identify it',
    ]),
    evidence: 'Scanner has a no-clear-flower state instead of forcing a confident flower result.',
  },
  {
    id: 'scanner-retake-guidance',
    area: 'photoQuality',
    pass: includesAll(indexHtml, [
      'natural light',
      'clean background',
      'only the flower centered',
      'Move closer to one open flower',
      'complete, open flower in focus',
      'mixed flowers',
    ]),
    evidence: 'Scanner tells users how to frame one clear flower before capture and retake better photos when confidence is weak.',
  },
  {
    id: 'scanner-touch-targets',
    area: 'mobileDesign',
    pass: pxValue(fabRule, 'width') >= 44 &&
      pxValue(fabRule, 'height') >= 44 &&
      pxValue(closeRule, 'width') >= 40 &&
      pxValue(closeRule, 'height') >= 40 &&
      pxValue(captureRule, 'width') >= 64 &&
      pxValue(captureRule, 'height') >= 64 &&
      pxValue(uploadButtonRule, 'padding') >= 12,
    evidence: 'Primary scanner controls meet practical mobile touch target sizing.',
  },
  {
    id: 'scanner-result-sheet-mobile-bounds',
    area: 'mobileDesign',
    pass: resultRule.includes('max-height: 70dvh') &&
      resultRule.includes('overflow-y: auto') &&
      careGridRule.includes('grid-template-columns: 1fr 1fr 1fr'),
    evidence: 'Result sheet stays bounded and scrollable on phone-sized viewports.',
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
  mobileScannerReady: failed.length === 0,
}, null, 2));

if (failed.length) {
  process.exitCode = 1;
}
