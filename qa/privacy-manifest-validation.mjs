const expectedCollectedDataEntryKeys = [
  'NSPrivacyCollectedDataType',
  'NSPrivacyCollectedDataTypeLinked',
  'NSPrivacyCollectedDataTypePurposes',
  'NSPrivacyCollectedDataTypeTracking',
];
const expectedAccessedApiEntryKeys = [
  'NSPrivacyAccessedAPIType',
  'NSPrivacyAccessedAPITypeReasons',
];
const userDefaultsApiType = 'NSPrivacyAccessedAPICategoryUserDefaults';
const userDefaultsReasons = ['CA92.1'];

export const expectedCollectedDataTypes = Object.freeze({
  NSPrivacyCollectedDataTypeEmailAddress: Object.freeze([
    'NSPrivacyCollectedDataTypePurposeAppFunctionality',
  ]),
  NSPrivacyCollectedDataTypeUserID: Object.freeze([
    'NSPrivacyCollectedDataTypePurposeAppFunctionality',
    'NSPrivacyCollectedDataTypePurposeAnalytics',
  ]),
  NSPrivacyCollectedDataTypeOtherUserContent: Object.freeze([
    'NSPrivacyCollectedDataTypePurposeAppFunctionality',
  ]),
  NSPrivacyCollectedDataTypePhotosorVideos: Object.freeze([
    'NSPrivacyCollectedDataTypePurposeAppFunctionality',
  ]),
  NSPrivacyCollectedDataTypeProductInteraction: Object.freeze([
    'NSPrivacyCollectedDataTypePurposeAppFunctionality',
    'NSPrivacyCollectedDataTypePurposeAnalytics',
  ]),
  NSPrivacyCollectedDataTypeOtherDataTypes: Object.freeze([
    'NSPrivacyCollectedDataTypePurposeAppFunctionality',
  ]),
});

function decodeXml(value) {
  return value
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');
}

export function parseXmlPlist(xml) {
  const source = xml
    .replace(/<\?xml[\s\S]*?\?>/g, '')
    .replace(/<!DOCTYPE[\s\S]*?>/g, '')
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/<\/?plist(?:\s[^>]*)?>/g, '');
  let position = 0;

  function skipWhitespace() {
    const whitespace = /^\s+/.exec(source.slice(position));
    if (whitespace) position += whitespace[0].length;
  }

  function consume(token) {
    skipWhitespace();
    if (!source.startsWith(token, position)) return false;
    position += token.length;
    return true;
  }

  function consumeTextElement(name) {
    skipWhitespace();
    const expression = new RegExp(`^<${name}>([\\s\\S]*?)<\\/${name}>`);
    const match = expression.exec(source.slice(position));
    if (!match) return null;
    position += match[0].length;
    return decodeXml(match[1]);
  }

  function parseValue() {
    skipWhitespace();

    if (consume('<dict/>') || consume('<dict />')) return {};
    if (consume('<dict>')) {
      const dictionary = {};
      while (!consume('</dict>')) {
        const key = consumeTextElement('key');
        if (key === null) throw new Error(`Expected plist key at offset ${position}`);
        if (Object.hasOwn(dictionary, key)) throw new Error(`Duplicate plist key: ${key}`);
        dictionary[key] = parseValue();
      }
      return dictionary;
    }

    if (consume('<array/>') || consume('<array />')) return [];
    if (consume('<array>')) {
      const array = [];
      while (!consume('</array>')) array.push(parseValue());
      return array;
    }

    const stringValue = consumeTextElement('string');
    if (stringValue !== null) return stringValue;
    if (consume('<true/>') || consume('<true />')) return true;
    if (consume('<false/>') || consume('<false />')) return false;

    throw new Error(`Unsupported plist value at offset ${position}`);
  }

  const value = parseValue();
  skipWhitespace();
  if (position !== source.length) throw new Error(`Unexpected plist content at offset ${position}`);
  return value;
}

function sortedUniqueStrings(value) {
  if (!Array.isArray(value) || value.some((item) => typeof item !== 'string')) return null;
  return [...new Set(value)].sort();
}

function sameStrings(actual, expected) {
  return actual.length === expected.length && actual.every((value, index) => value === expected[index]);
}

function invalidManifestRoot(manifest) {
  return !manifest || typeof manifest !== 'object' || Array.isArray(manifest);
}

export function validatePrivacyCollectedDataTypes(manifest) {
  const errors = [];

  if (invalidManifestRoot(manifest)) {
    return ['Privacy manifest root must be a dictionary'];
  }

  if (manifest.NSPrivacyTracking !== false) {
    errors.push('NSPrivacyTracking must be false');
  }
  if (!Array.isArray(manifest.NSPrivacyTrackingDomains) || manifest.NSPrivacyTrackingDomains.length !== 0) {
    errors.push('NSPrivacyTrackingDomains must be an empty array');
  }

  const collectedDataTypes = manifest.NSPrivacyCollectedDataTypes;
  if (!Array.isArray(collectedDataTypes)) {
    errors.push('NSPrivacyCollectedDataTypes must be an array');
    return errors;
  }

  const seenTypes = new Set();
  for (const [index, entry] of collectedDataTypes.entries()) {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
      errors.push(`Collected data entry ${index} must be a dictionary`);
      continue;
    }

    const entryKeys = Object.keys(entry).sort();
    if (!sameStrings(entryKeys, expectedCollectedDataEntryKeys)) {
      errors.push(`Collected data entry ${index} must contain only Apple's four required declaration keys`);
    }

    const type = entry.NSPrivacyCollectedDataType;
    if (typeof type !== 'string' || !Object.hasOwn(expectedCollectedDataTypes, type)) {
      errors.push(`Collected data entry ${index} has an unexpected data type: ${String(type)}`);
      continue;
    }
    if (seenTypes.has(type)) {
      errors.push(`Collected data type is declared more than once: ${type}`);
      continue;
    }
    seenTypes.add(type);

    if (entry.NSPrivacyCollectedDataTypeLinked !== true) {
      errors.push(`${type} must be linked to the user`);
    }
    if (entry.NSPrivacyCollectedDataTypeTracking !== false) {
      errors.push(`${type} must not be used for tracking`);
    }

    const purposes = sortedUniqueStrings(entry.NSPrivacyCollectedDataTypePurposes);
    const expectedPurposes = [...expectedCollectedDataTypes[type]].sort();
    if (purposes === null || !sameStrings(purposes, expectedPurposes)) {
      errors.push(`${type} purposes must be exactly: ${expectedPurposes.join(', ')}`);
    } else if (purposes.length !== entry.NSPrivacyCollectedDataTypePurposes.length) {
      errors.push(`${type} purposes must not contain duplicates`);
    }
  }

  for (const expectedType of Object.keys(expectedCollectedDataTypes)) {
    if (!seenTypes.has(expectedType)) errors.push(`Missing collected data type: ${expectedType}`);
  }

  return errors;
}

export function validatePrivacyAccessedApiTypes(manifest) {
  const errors = [];

  if (invalidManifestRoot(manifest)) {
    return ['Privacy manifest root must be a dictionary'];
  }

  const declarations = manifest.NSPrivacyAccessedAPITypes;
  if (!Array.isArray(declarations)) {
    return ['NSPrivacyAccessedAPITypes must be an array'];
  }
  if (declarations.length !== 1) {
    errors.push('NSPrivacyAccessedAPITypes must contain exactly one UserDefaults declaration');
  }

  const seenApiTypes = new Set();
  for (const [index, declaration] of declarations.entries()) {
    if (!declaration || typeof declaration !== 'object' || Array.isArray(declaration)) {
      errors.push(`Accessed API entry ${index} must be a dictionary`);
      continue;
    }

    const entryKeys = Object.keys(declaration).sort();
    if (!sameStrings(entryKeys, expectedAccessedApiEntryKeys)) {
      errors.push(`Accessed API entry ${index} must contain only Apple's two required declaration keys`);
    }

    const apiType = declaration.NSPrivacyAccessedAPIType;
    if (apiType !== userDefaultsApiType) {
      errors.push(`Accessed API entry ${index} must declare exactly ${userDefaultsApiType}`);
    }
    if (seenApiTypes.has(apiType)) {
      errors.push(`Accessed API type is declared more than once: ${String(apiType)}`);
    }
    seenApiTypes.add(apiType);

    const reasons = sortedUniqueStrings(declaration.NSPrivacyAccessedAPITypeReasons);
    if (reasons === null || !sameStrings(reasons, userDefaultsReasons)) {
      errors.push(`${String(apiType)} reasons must be exactly: ${userDefaultsReasons.join(', ')}`);
    } else if (reasons.length !== declaration.NSPrivacyAccessedAPITypeReasons.length) {
      errors.push(`${String(apiType)} reasons must not contain duplicates`);
    }
  }

  return errors;
}

export function validatePrivacyManifest(manifest) {
  if (invalidManifestRoot(manifest)) {
    return ['Privacy manifest root must be a dictionary'];
  }
  return [
    ...validatePrivacyCollectedDataTypes(manifest),
    ...validatePrivacyAccessedApiTypes(manifest),
  ];
}
