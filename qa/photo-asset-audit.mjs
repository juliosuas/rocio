import fs from 'node:fs';
import path from 'node:path';

const repoRoot = path.resolve(new URL('.', import.meta.url).pathname, '..');
const attributionsPath = path.join(repoRoot, 'PHOTO_ATTRIBUTIONS.md');
const flowersDir = path.join(repoRoot, 'assets', 'flowers');
const requireAppStoreReady = process.argv.includes('--app-store-ready');
const maxAppStorePhotoBytes = 1_000_000;

const catalogPhotoIds = [
  'cempasuchil',
  'clavel',
  'gardenia',
  'geranio',
  'girasol',
  'hortensia',
  'jazmin',
  'lavanda',
  'lirio',
  'margarita',
  'orquidea',
  'petunia',
  'rosa',
  'tulipan',
  'violeta',
];

function readJpegDimensions(filePath) {
  const buffer = fs.readFileSync(filePath);

  if (buffer[0] !== 0xff || buffer[1] !== 0xd8) {
    throw new Error(`${filePath} is not a JPEG`);
  }

  let offset = 2;
  while (offset < buffer.length) {
    if (buffer[offset] !== 0xff) {
      offset += 1;
      continue;
    }
    if (offset + 3 >= buffer.length) {
      break;
    }

    const marker = buffer[offset + 1];
    const length = buffer.readUInt16BE(offset + 2);
    const isStartOfFrame = marker >= 0xc0 && marker <= 0xc3;

    if (isStartOfFrame) {
      if (offset + 8 >= buffer.length) {
        break;
      }
      return {
        width: buffer.readUInt16BE(offset + 7),
        height: buffer.readUInt16BE(offset + 5),
      };
    }

    offset += 2 + length;
  }

  throw new Error(`Could not read JPEG dimensions for ${filePath}`);
}

const attributionText = fs.readFileSync(attributionsPath, 'utf8');
const rows = catalogPhotoIds.map((id) => {
  const relativePath = `assets/flowers/${id}.jpg`;
  const filePath = path.join(flowersDir, `${id}.jpg`);
  const exists = fs.existsSync(filePath);
  const byteSize = exists ? fs.statSync(filePath).size : 0;
  const dimensions = exists ? readJpegDimensions(filePath) : null;
  const attributed = attributionText.includes(relativePath);
  const line = attributionText
    .split('\n')
    .find((entry) => entry.includes(relativePath)) || '';
  const pendingLicense = /PENDING/i.test(line) || !attributed;
  const lowResolution = dimensions
    ? dimensions.width < 800 || dimensions.height < 800
    : true;
  const oversized = byteSize > maxAppStorePhotoBytes;

  return {
    id,
    exists,
    size: dimensions ? `${dimensions.width}x${dimensions.height}` : 'missing',
    payload: exists ? `${Math.round(byteSize / 1024)} KB` : 'missing',
    attributed,
    pendingLicense,
    lowResolution,
    oversized,
  };
});

const missing = rows.filter((row) => !row.exists || !row.attributed);
const pending = rows.filter((row) => row.pendingLicense);
const lowResolution = rows.filter((row) => row.lowResolution);
const oversized = rows.filter((row) => row.oversized);
const appStoreBlocked = [...new Set([
  ...pending.map((row) => row.id),
  ...lowResolution.map((row) => row.id),
  ...oversized.map((row) => row.id),
])].sort();

console.table(rows);
console.log(JSON.stringify({
  total: rows.length,
  present: rows.filter((row) => row.exists).length,
  attributed: rows.filter((row) => row.attributed).length,
  pendingLicenseAudit: pending.map((row) => row.id),
  lowResolution: lowResolution.map((row) => row.id),
  oversized: oversized.map((row) => row.id),
  maxAppStorePhotoBytes,
  appStoreReady: appStoreBlocked.length === 0,
  appStoreBlocked,
  pass: missing.length === 0,
}, null, 2));

if (missing.length || (requireAppStoreReady && appStoreBlocked.length)) {
  process.exitCode = 1;
}
