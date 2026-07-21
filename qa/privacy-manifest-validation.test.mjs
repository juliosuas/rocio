import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { parseXmlPlist, validatePrivacyManifest } from './privacy-manifest-validation.mjs';

const projectRoot = path.resolve(import.meta.dirname, '..');
const manifestXml = fs.readFileSync(
  path.join(projectRoot, 'ios', 'Rocio', 'Resources', 'PrivacyInfo.xcprivacy'),
  'utf8',
);
const validManifest = parseXmlPlist(manifestXml);

function cloneManifest() {
  return structuredClone(validManifest);
}

function entry(manifest, type) {
  return manifest.NSPrivacyCollectedDataTypes.find(
    (candidate) => candidate.NSPrivacyCollectedDataType === type,
  );
}

test('the checked-in privacy manifest matches the documented data declarations', () => {
  assert.deepEqual(validatePrivacyManifest(validManifest), []);
});

test('rejects a missing collected data category', () => {
  const manifest = cloneManifest();
  manifest.NSPrivacyCollectedDataTypes = manifest.NSPrivacyCollectedDataTypes.filter(
    (candidate) => candidate.NSPrivacyCollectedDataType !== 'NSPrivacyCollectedDataTypeOtherDataTypes',
  );

  assert.ok(validatePrivacyManifest(manifest).some((error) => error.includes('Missing collected data type')));
});

test('rejects data that is not linked to the user', () => {
  const manifest = cloneManifest();
  entry(manifest, 'NSPrivacyCollectedDataTypeOtherUserContent').NSPrivacyCollectedDataTypeLinked = false;

  assert.ok(validatePrivacyManifest(manifest).some((error) => error.includes('must be linked to the user')));
});

test('rejects per-category or root tracking', () => {
  const manifest = cloneManifest();
  manifest.NSPrivacyTracking = true;
  entry(manifest, 'NSPrivacyCollectedDataTypePhotosorVideos').NSPrivacyCollectedDataTypeTracking = true;

  const errors = validatePrivacyManifest(manifest);
  assert.ok(errors.includes('NSPrivacyTracking must be false'));
  assert.ok(errors.some((error) => error.includes('must not be used for tracking')));
});

test('rejects incorrect purposes', () => {
  const manifest = cloneManifest();
  entry(manifest, 'NSPrivacyCollectedDataTypeProductInteraction').NSPrivacyCollectedDataTypePurposes = [
    'NSPrivacyCollectedDataTypePurposeAppFunctionality',
  ];

  assert.ok(validatePrivacyManifest(manifest).some((error) => error.includes('purposes must be exactly')));
});

test('rejects a missing UserDefaults API declaration', () => {
  const manifest = cloneManifest();
  manifest.NSPrivacyAccessedAPITypes = [];

  assert.ok(validatePrivacyManifest(manifest).some((error) => error.includes('exactly one UserDefaults')));
});

test('rejects duplicate UserDefaults API declarations', () => {
  const manifest = cloneManifest();
  manifest.NSPrivacyAccessedAPITypes.push(structuredClone(manifest.NSPrivacyAccessedAPITypes[0]));

  const errors = validatePrivacyManifest(manifest);
  assert.ok(errors.some((error) => error.includes('exactly one UserDefaults')));
  assert.ok(errors.some((error) => error.includes('declared more than once')));
});

test('rejects an extra accessed API type', () => {
  const manifest = cloneManifest();
  manifest.NSPrivacyAccessedAPITypes.push({
    NSPrivacyAccessedAPIType: 'NSPrivacyAccessedAPICategoryFileTimestamp',
    NSPrivacyAccessedAPITypeReasons: ['C617.1'],
  });

  const errors = validatePrivacyManifest(manifest);
  assert.ok(errors.some((error) => error.includes('exactly one UserDefaults')));
  assert.ok(errors.some((error) => error.includes('must declare exactly')));
});

test('rejects incorrect or duplicate UserDefaults reasons', () => {
  const incorrectManifest = cloneManifest();
  incorrectManifest.NSPrivacyAccessedAPITypes[0].NSPrivacyAccessedAPITypeReasons = ['CA92.2'];
  assert.ok(validatePrivacyManifest(incorrectManifest).some((error) => error.includes('reasons must be exactly')));

  const duplicateManifest = cloneManifest();
  duplicateManifest.NSPrivacyAccessedAPITypes[0].NSPrivacyAccessedAPITypeReasons = ['CA92.1', 'CA92.1'];
  assert.ok(validatePrivacyManifest(duplicateManifest).some((error) => error.includes('must not contain duplicates')));
});

test('rejects unexpected keys in an accessed API declaration', () => {
  const manifest = cloneManifest();
  manifest.NSPrivacyAccessedAPITypes[0].UnexpectedKey = false;

  assert.ok(validatePrivacyManifest(manifest).some((error) => error.includes("Apple's two required declaration keys")));
});
