import fs from 'node:fs';
import path from 'node:path';

import {
  parseXmlPlist,
  validatePrivacyAccessedApiTypes,
  validatePrivacyCollectedDataTypes,
} from './privacy-manifest-validation.mjs';

const projectRoot = path.resolve(import.meta.dirname, '..');
const iosRoot = path.join(projectRoot, 'ios', 'Rocio');
const projectFile = fs.readFileSync(path.join(projectRoot, 'ios', 'Rocio.xcodeproj', 'project.pbxproj'), 'utf8');
const appInfoPlist = fs.readFileSync(path.join(iosRoot, 'Resources', 'Info.plist'), 'utf8');
const privacyManifest = fs.readFileSync(path.join(iosRoot, 'Resources', 'PrivacyInfo.xcprivacy'), 'utf8');
let parsedPrivacyManifest = null;
let privacyManifestParseError = null;
try {
  parsedPrivacyManifest = parseXmlPlist(privacyManifest);
} catch (error) {
  privacyManifestParseError = error instanceof Error ? error.message : String(error);
}
const privacyCollectedDataErrors = privacyManifestParseError
  ? [`Invalid privacy manifest: ${privacyManifestParseError}`]
  : validatePrivacyCollectedDataTypes(parsedPrivacyManifest);
const privacyAccessedApiErrors = privacyManifestParseError
  ? [`Invalid privacy manifest: ${privacyManifestParseError}`]
  : validatePrivacyAccessedApiTypes(parsedPrivacyManifest);
const privacyManifestErrors = [...privacyCollectedDataErrors, ...privacyAccessedApiErrors];
const settingsView = fs.readFileSync(path.join(iosRoot, 'Views', 'Settings', 'SettingsView.swift'), 'utf8');
const scannerView = fs.readFileSync(path.join(iosRoot, 'Views', 'Scanner', 'ScannerView.swift'), 'utf8');
const backendConfigurationSource = fs.readFileSync(
  path.join(iosRoot, 'Services', 'BackendConfiguration.swift'),
  'utf8',
);
const passwordRecoverySources = [
  path.join(iosRoot, 'Services', 'BackendConfiguration.swift'),
  path.join(iosRoot, 'Services', 'KeychainSessionStore.swift'),
  path.join(iosRoot, 'Services', 'RocioBackendClient.swift'),
].map((filePath) => fs.readFileSync(filePath, 'utf8')).join('\n');
const stringCatalogPath = path.join(iosRoot, 'Resources', 'Localizable.xcstrings');
const stringCatalog = fs.existsSync(stringCatalogPath)
  ? JSON.parse(fs.readFileSync(stringCatalogPath, 'utf8'))
  : { strings: {} };
const appShortcutsCatalogPath = path.join(iosRoot, 'Resources', 'AppShortcuts.xcstrings');
const appShortcutsCatalog = fs.existsSync(appShortcutsCatalogPath)
  ? JSON.parse(fs.readFileSync(appShortcutsCatalogPath, 'utf8'))
  : { strings: {} };
const infoPlistCatalogPath = path.join(iosRoot, 'Resources', 'InfoPlist.xcstrings');
const infoPlistCatalog = fs.existsSync(infoPlistCatalogPath)
  ? JSON.parse(fs.readFileSync(infoPlistCatalogPath, 'utf8'))
  : { strings: {} };
const iconsDirectory = path.join(iosRoot, 'Resources', 'Assets.xcassets', 'AppIcon.appiconset');
const iconFiles = fs.readdirSync(iconsDirectory).filter((name) => name.endsWith('.png'));

function filesRecursively(directory, extension) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) return filesRecursively(entryPath, extension);
    return entry.name.endsWith(extension) ? [entryPath] : [];
  });
}

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
];
const missingLocalizationKeys = requiredLocalizationKeys.filter((key) => !stringCatalog.strings[key]);
const incompleteLocalizationKeys = requiredLocalizationKeys.filter((key) => {
  const localizations = stringCatalog.strings[key]?.localizations ?? {};
  return !localizations.en?.stringUnit?.value || !localizations.es?.stringUnit?.value;
});
const usedLocalizationKeys = [...new Set(filesRecursively(iosRoot, '.swift').flatMap((filePath) => {
  const source = fs.readFileSync(filePath, 'utf8');
  return [...source.matchAll(/L10n\.(?:text|format)\("([^"]+)/g)]
    .map((match) => match[1])
    .filter((key) => !key.includes('\\('));
}))].sort();
const missingUsedLocalizationKeys = usedLocalizationKeys.filter((key) => !stringCatalog.strings[key]);
const incompleteUsedLocalizationKeys = usedLocalizationKeys.filter((key) => {
  const localizations = stringCatalog.strings[key]?.localizations ?? {};
  return !localizations.en?.stringUnit?.value || !localizations.es?.stringUnit?.value;
});
const requiredAppShortcutKeys = [
  'Open my garden in ${applicationName}',
  'Show my garden in ${applicationName}',
  'Water a plant in ${applicationName}',
  'Log watering in ${applicationName}',
  'Scan a plant with ${applicationName}',
  'Identify a plant in ${applicationName}',
];
const incompleteAppShortcutKeys = requiredAppShortcutKeys.filter((key) => {
  const localizations = appShortcutsCatalog.strings[key]?.localizations ?? {};
  return !localizations.en?.stringUnit?.value || !localizations.es?.stringUnit?.value;
});
const localizedPurposeStringIsComplete = (key) => {
  const localizations = infoPlistCatalog.strings[key]?.localizations ?? {};
  const english = localizations.en?.stringUnit?.value ?? '';
  const spanish = localizations.es?.stringUnit?.value ?? '';
  return english.toLowerCase().includes('plant')
    && spanish.toLowerCase().includes('planta');
};

const checks = [
  ['bundle id', projectFile.includes('PRODUCT_BUNDLE_IDENTIFIER = com.juliosuas.rocio;')],
  ['marketing version', projectFile.includes('MARKETING_VERSION = 1.0;')],
  [
    'camera purpose string localized for plants',
    appInfoPlist.includes('<key>NSCameraUsageDescription</key>')
      && appInfoPlist.includes('Rocio uses the camera to photograph plants')
      && projectFile.includes('InfoPlist.xcstrings')
      && localizedPurposeStringIsComplete('NSCameraUsageDescription'),
  ],
  [
    'photo purpose string localized for plants',
    appInfoPlist.includes('<key>NSPhotoLibraryUsageDescription</key>')
      && appInfoPlist.includes('Rocio uses photos you choose to identify plants')
      && projectFile.includes('InfoPlist.xcstrings')
      && localizedPurposeStringIsComplete('NSPhotoLibraryUsageDescription'),
  ],
  [
    'password recovery URL scheme',
    appInfoPlist.includes('<key>CFBundleURLSchemes</key>')
      && appInfoPlist.includes('<string>com.juliosuas.rocio</string>'),
  ],
  [
    'app route URL scheme',
    appInfoPlist.includes('<string>rocio</string>'),
  ],
  [
    'password recovery uses PKCE instead of URL bearer tokens',
    passwordRecoverySources.includes('grant_type=pkce')
      && passwordRecoverySources.includes('codeChallengeMethod: "s256"')
      && passwordRecoverySources.includes('PasswordRecoveryCodeVerifierStore')
      && passwordRecoverySources.includes('let authorizationCode: String')
      && !backendConfigurationSource.includes('let accessToken: String'),
  ],
  ['privacy manifest collected data declarations', privacyCollectedDataErrors.length === 0],
  ['privacy manifest UserDefaults declaration', privacyAccessedApiErrors.length === 0],
  ['English localization region', /knownRegions = \([\s\S]*\ben,/.test(projectFile)],
  ['Spanish localization region', /knownRegions = \([\s\S]*\bes,/.test(projectFile)],
  ['string catalog included', projectFile.includes('Localizable.xcstrings') && fs.existsSync(stringCatalogPath)],
  ['catalog and critical copy localized EN/ES', missingLocalizationKeys.length === 0 && incompleteLocalizationKeys.length === 0],
  ['all static app copy localized EN/ES', missingUsedLocalizationKeys.length === 0 && incompleteUsedLocalizationKeys.length === 0],
  ['App Shortcuts catalog localized EN/ES', projectFile.includes('AppShortcuts.xcstrings') && incompleteAppShortcutKeys.length === 0],
  ['localization helper included', projectFile.includes('Localization.swift') && fs.existsSync(path.join(iosRoot, 'Localization.swift'))],
  ['1024 marketing icon', fs.existsSync(path.join(iconsDirectory, 'AppIcon-1024.png'))],
  ['all app icons opaque', alphaIcons.length === 0],
  ['no internal launch copy in Settings', !/Pendiente antes de publicar|Apple Developer Team|capturas finales/i.test(settingsView)],
  [
    'scanner work survives tab switches',
    scannerView.includes('@StateObject private var analysisCoordinator')
      && !/\.onDisappear\s*\{[\s\S]{0,240}(?:cancelImageLoad|analysisCoordinator\.cancel)/.test(scannerView),
  ],
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
  missingUsedLocalizationKeys,
  incompleteUsedLocalizationKeys,
  incompleteAppShortcutKeys,
  infoPlistLocalizationKeys: Object.keys(infoPlistCatalog.strings),
  privacyManifestErrors,
  unsignedReady: failed === 0,
  signedReady: failed === 0 && Boolean(configuredTeam),
  signingBlocker: configuredTeam ? null : 'DEVELOPMENT_TEAM is not configured',
}, null, 2));

if (failed) process.exit(1);
