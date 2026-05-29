import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const projectRoot = path.resolve(import.meta.dirname, '..');
const indexHtml = fs.readFileSync(path.join(projectRoot, 'index.html'), 'utf8');

const flowersStart = indexHtml.indexOf('const FLOWERS = [');
const flowersEnd = indexHtml.indexOf('];', flowersStart);

if (flowersStart < 0 || flowersEnd < 0) {
  throw new Error('Could not locate FLOWERS catalog in index.html');
}

const flowersBlock = indexHtml.slice(flowersStart, flowersEnd);
const flowerIds = [...flowersBlock.matchAll(/\bid:'([^']+)'/g)]
  .map(match => match[1])
  .filter((id, index, ids) => ids.indexOf(id) === index);

const classifierStart = indexHtml.indexOf('const FLOWER_COLOR_PROFILES = {');
const classifierEnd = indexHtml.indexOf('const ROCIO_SUPABASE_URL', classifierStart);

if (classifierStart < 0 || classifierEnd < 0) {
  throw new Error('Could not locate local classifier block in index.html');
}

const classifierBlock = indexHtml
  .slice(classifierStart, classifierEnd)
  .replace('const FLOWER_COLOR_PROFILES', 'var FLOWER_COLOR_PROFILES');

const context = {
  FLOWERS: flowerIds.map(id => ({ id })),
};

vm.createContext(context);
vm.runInContext(classifierBlock, context, { filename: 'index.html.local-classifier.js' });

const RGB = {
  white: [244, 241, 226],
  brightWhite: [252, 251, 246],
  cream: [245, 225, 176],
  green: [78, 132, 60],
  lightGreen: [142, 181, 105],
  darkGreen: [34, 82, 44],
  yellow: [245, 205, 47],
  brightYellow: [255, 220, 35],
  orange: [231, 123, 38],
  deepOrange: [222, 88, 22],
  red: [207, 51, 60],
  pink: [224, 103, 155],
  purple: [138, 91, 178],
  deepPurple: [92, 57, 132],
  blue: [87, 126, 193],
  brown: [85, 55, 31],
};

const scenarios = [
  {
    name: 'lily_control_white_orange_green',
    expected: 'lirio',
    note: 'Positive control shaped like the current lirio color profile.',
    colors: [['white', 8], ['orange', 7], ['green', 6]],
  },
  {
    name: 'gardenia_white_dark_green',
    expected: 'gardenia',
    note: 'White petals with dark green leaves; should not collapse into lirio.',
    colors: [['brightWhite', 14], ['darkGreen', 7]],
  },
  {
    name: 'jazmin_white_light_green',
    expected: 'jazmin',
    note: 'White petals with lighter foliage; common false-positive neighbor for lirio.',
    colors: [['white', 13], ['lightGreen', 8]],
  },
  {
    name: 'margarita_white_yellow',
    expected: 'margarita',
    note: 'Daisy-like white/yellow distribution.',
    colors: [['white', 12], ['yellow', 9]],
  },
  {
    name: 'cempasuchil_orange_yellow',
    expected: 'cempasuchil',
    note: 'Orange/yellow marigold-like distribution.',
    colors: [['deepOrange', 14], ['yellow', 7]],
  },
  {
    name: 'tulipan_red_orange',
    expected: 'tulipan',
    note: 'Red/orange tulip-like distribution.',
    colors: [['red', 11], ['orange', 10]],
  },
  {
    name: 'girasol_yellow_brown',
    expected: 'girasol',
    note: 'Sunflower-like yellow plus brown center.',
    colors: [['brightYellow', 15], ['brown', 6]],
  },
  {
    name: 'hortensia_blue_purple',
    expected: 'hortensia',
    note: 'Hydrangea-like cool color cluster.',
    colors: [['blue', 11], ['purple', 10]],
  },
  {
    name: 'violeta_deep_purple',
    expected: 'violeta',
    note: 'Violet-like deep purple distribution.',
    colors: [['deepPurple', 16], ['blue', 5]],
  },
  {
    name: 'geranio_red_green',
    expected: 'geranio',
    note: 'Geranium-like red with saturated green.',
    colors: [['red', 13], ['green', 8]],
  },
  {
    name: 'unknown_white_green_orange_mixed',
    expectedNot: 'lirio',
    note: 'Ambiguous non-lily stress case: similar palette but no shape evidence.',
    colors: [['white', 7], ['green', 7], ['orange', 7]],
  },
  {
    name: 'unknown_pale_green_white',
    expectedNot: 'lirio',
    note: 'Generic pale flower/leaf image; should be uncertain and not over-routed to lirio.',
    colors: [['cream', 6], ['white', 8], ['lightGreen', 7]],
  },
];

const sweepPalette = ['white', 'cream', 'green', 'lightGreen', 'orange', 'deepOrange', 'yellow'];
const sweepResults = [];

for (let a = 0; a < sweepPalette.length; a += 1) {
  for (let b = a + 1; b < sweepPalette.length; b += 1) {
    for (let c = b + 1; c < sweepPalette.length; c += 1) {
      for (const weights of [[9, 6, 6], [7, 7, 7], [11, 5, 5], [5, 11, 5], [5, 5, 11]]) {
        const colors = [
          [sweepPalette[a], weights[0]],
          [sweepPalette[b], weights[1]],
          [sweepPalette[c], weights[2]],
        ];
        const result = context.identifyPlant(makeSyntheticCanvas(expandColors(colors)));
        if (result.flowerId === 'lirio') {
          sweepResults.push({
            palette: colors.map(([name, count]) => `${name}:${count}`).join('+'),
            confidence: result.confidence,
            uncertain: result.isUncertain,
            topCandidates: result.candidates.map(candidate => candidate.flowerId).join(','),
          });
        }
      }
    }
  }
}

function expandColors(spec) {
  return spec.flatMap(([name, count]) => Array.from({ length: count }, () => RGB[name]));
}

function makeSyntheticCanvas(colors) {
  let callIndex = 0;
  return {
    width: 240,
    height: 240,
    getContext(type) {
      if (type !== '2d') throw new Error(`Unexpected context type: ${type}`);
      return {
        getImageData(_x, _y, w, h) {
          const color = colors[callIndex % colors.length];
          callIndex += 1;
          const data = new Uint8ClampedArray(w * h * 4);
          for (let i = 0; i < data.length; i += 4) {
            data[i] = color[0];
            data[i + 1] = color[1];
            data[i + 2] = color[2];
            data[i + 3] = 255;
          }
          return { data };
        },
      };
    },
  };
}

function passStatus(scenario, result) {
  if (scenario.expected) return result.flowerId === scenario.expected;
  if (scenario.expectedNot) return result.flowerId !== scenario.expectedNot;
  return true;
}

const results = scenarios.map(scenario => {
  const canvas = makeSyntheticCanvas(expandColors(scenario.colors));
  const result = context.identifyPlant(canvas);
  const topCandidates = result.candidates.map(candidate => candidate.flowerId).join(',');
  return {
    scenario: scenario.name,
    expected: scenario.expected || `not:${scenario.expectedNot}`,
    actual: result.flowerId,
    confidence: result.confidence,
    uncertain: result.isUncertain,
    topCandidates,
    pass: passStatus(scenario, result),
    note: scenario.note,
  };
});

const nonLilyFailures = results.filter(row => {
  const isNonLily = row.expected !== 'lirio';
  return isNonLily && row.actual === 'lirio';
});

console.table(results.map(({ note, ...row }) => row));
console.log('Lirio top-result sweep hits from non-lily palettes:');
console.table(sweepResults);
console.log(JSON.stringify({
  total: results.length,
  passed: results.filter(row => row.pass).length,
  failed: results.filter(row => !row.pass).length,
  nonLilyClassifiedAsLirio: nonLilyFailures.length,
  nonLilyLirioScenarios: nonLilyFailures.map(row => row.scenario),
  nonLilyPaletteSweepClassifiedAsLirio: sweepResults.length,
}, null, 2));

if (process.argv.includes('--strict')) {
  const failed = results.filter(row => !row.pass);
  if (failed.length || sweepResults.length) process.exitCode = 1;
}
