import fs from 'node:fs';
import path from 'node:path';

const projectRoot = path.resolve(import.meta.dirname, '..');
const iosRoot = path.join(projectRoot, 'ios', 'Rocio');
const projectFile = fs.readFileSync(path.join(projectRoot, 'ios', 'Rocio.xcodeproj', 'project.pbxproj'), 'utf8');
const privacyManifest = fs.readFileSync(path.join(iosRoot, 'Resources', 'PrivacyInfo.xcprivacy'), 'utf8');
const settingsView = fs.readFileSync(path.join(iosRoot, 'Views', 'Settings', 'SettingsView.swift'), 'utf8');
const stringCatalogPath = path.join(iosRoot, 'Resources', 'Localizable.xcstrings');
const stringCatalog = fs.existsSync(stringCatalogPath)
  ? JSON.parse(fs.readFileSync(stringCatalogPath, 'utf8'))
  : { strings: {} };
const iconsDirectory = path.join(iosRoot, 'Resources', 'Assets.xcassets', 'AppIcon.appiconset');
const iconFiles = fs.readdirSync(iconsDirectory).filter((name) => name.endsWith('.png'));

function pngHasAlpha(filePath) {
  const buffer = fs.readFileSync(filePath);
  const pngSignature = '89504e470d0a1a0a';
  if (buffer.subarray(0, 8).toString('hex') !== pngSignature || buffer.length < 26) {
    throw new Error(`Invalid PNG: ${filePath}`);
  }
  const colorType = buffer[25];
  return colorType === 4 || colorType === 6;
}

const alphaIcons = iconFiles.filter((name) => pngHasAlpha(path.join(iconsDirectory, name)));
const teamMatches = [...projectFile.matchAll(/DEVELOPMENT_TEAM = ([^;]*);/g)]
  .map((match) => match[1].trim().replaceAll('"', ''));
const configuredTeam = teamMatches.find(Boolean) ?? '';
const flowerIds = [
  'rosa', 'tulipan', 'orquidea', 'girasol', 'lavanda',
  'gardenia', 'jazmin', 'hortensia', 'lirio', 'margarita',
  'clavel', 'violeta', 'geranio', 'petunia', 'cempasuchil',
];
const flowerFields = [
  'name', 'soil', 'season', 'fact', 'toxicity', 'fertilizer',
  'pruning', 'propagation', 'companions', 'planting.1', 'planting.2', 'planting.3',
];
const requiredLocalizationKeys = [
  ...flowerIds.flatMap((id) => flowerFields.map((field) => `flower.${id}.${field}`)),
  'onboarding.subtitle',
  'scanner.disclaimer',
  'settings.privacy.copy',
  'notification.watering.body',
  'Open My Garden',
  'Open my garden in ${applicationName}',
  'Show my garden in ${applicationName}',
  'Log watering in ${applicationName}',
  'Scan a flower with ${applicationName}',
  'Identify a flower in ${applicationName}',
];
const missingLocalizationKeys = requiredLocalizationKeys.filter((key) => !stringCatalog.strings[key]);
const incompleteLocalizationKeys = requiredLocalizationKeys.filter((key) => {
  const localizations = stringCatalog.strings[key]?.localizations ?? {};
  return !localizations.en?.stringUnit?.value || !localizations.es?.stringUnit?.value;
});

const checks = [
  ['bundle id', projectFile.includes('PRODUCT_BUNDLE_IDENTIFIER = com.juliosuas.rocio;')],
  ['marketing version', projectFile.includes('MARKETING_VERSION = 1.0;')],
  ['camera purpose string', projectFile.includes('INFOPLIST_KEY_NSCameraUsageDescription')],
  ['photo purpose string', projectFile.includes('INFOPLIST_KEY_NSPhotoLibraryUsageDescription')],
  ['privacy manifest', privacyManifest.includes('NSPrivacyAccessedAPICategoryUserDefaults') && privacyManifest.includes('CA92.1')],
  ['English localization region', /knownRegions = \([\s\S]*\ben,/.test(projectFile)],
  ['Spanish localization region', /knownRegions = \([\s\S]*\bes,/.test(projectFile)],
  ['string catalog included', projectFile.includes('Localizable.xcstrings') && fs.existsSync(stringCatalogPath)],
  ['catalog and critical copy localized EN/ES', missingLocalizationKeys.length === 0 && incompleteLocalizationKeys.length === 0],
  ['localization helper included', projectFile.includes('Localization.swift') && fs.existsSync(path.join(iosRoot, 'Localization.swift'))],
  ['1024 marketing icon', fs.existsSync(path.join(iconsDirectory, 'AppIcon-1024.png'))],
  ['all app icons opaque', alphaIcons.length === 0],
  ['no internal launch copy in Settings', !/Pendiente antes de publicar|Apple Developer Team|capturas finales/i.test(settingsView)],
];

let failed = 0;
for (const [label, pass] of checks) {
  console.log(`${pass ? 'PASS' : 'FAIL'} ${label}`);
  if (!pass) failed += 1;
}

console.log(JSON.stringify({
  checks: checks.length,
  passed: checks.length - failed,
  failed: checks.filter(([, pass]) => !pass).map(([label]) => label),
  alphaIcons,
  missingLocalizationKeys,
  incompleteLocalizationKeys,
  unsignedReady: failed === 0,
  signedReady: failed === 0 && Boolean(configuredTeam),
  signingBlocker: configuredTeam ? null : 'DEVELOPMENT_TEAM is not configured',
}, null, 2));

if (failed) process.exit(1);
