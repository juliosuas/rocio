import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const projectRoot = path.resolve(import.meta.dirname, '..');
const indexHtml = fs.readFileSync(path.join(projectRoot, 'index.html'), 'utf8');

function extractConstInitializer(source, name) {
  const marker = `const ${name} = `;
  const start = source.indexOf(marker);
  if (start === -1) throw new Error(`Missing ${marker}`);

  const initializerStart = start + marker.length;
  const opening = source[initializerStart];
  const matching = opening === '[' ? ']' : opening === '{' ? '}' : null;
  if (!matching) throw new Error(`${name} does not start with an array/object initializer`);

  let depth = 0;
  let quote = null;
  let escaped = false;

  for (let i = initializerStart; i < source.length; i += 1) {
    const char = source[i];

    if (quote) {
      if (escaped) {
        escaped = false;
      } else if (char === '\\') {
        escaped = true;
      } else if (char === quote) {
        quote = null;
      }
      continue;
    }

    if (char === '\'' || char === '"' || char === '`') {
      quote = char;
      continue;
    }

    if (char === opening) depth += 1;
    if (char === matching) {
      depth -= 1;
      if (depth === 0) return source.slice(initializerStart, i + 1);
    }
  }

  throw new Error(`Could not find end of ${name}`);
}

function evaluateInitializer(name) {
  const context = {
    rocioFlowerImage: (id) => `assets/flowers/${id}.jpg`,
  };
  vm.createContext(context);
  const initializer = extractConstInitializer(indexHtml, name);
  return vm.runInContext(`(${initializer})`, context, { timeout: 1000 });
}

const flowers = evaluateInitializer('FLOWERS');
const symptoms = evaluateInitializer('SYMPTOMS');

const flowerRows = flowers.map((flower) => {
  const diseases = Array.isArray(flower.diseases) ? flower.diseases : [];
  const completeDiseases = diseases.filter((disease) =>
    disease?.name && disease?.symptom && disease?.treatment
  );

  return {
    id: flower.id,
    diseases: diseases.length,
    complete: completeDiseases.length,
    pass: diseases.length >= 2 && completeDiseases.length === diseases.length,
  };
});

const symptomRows = symptoms.map((symptom) => {
  const causes = Array.isArray(symptom.causes) ? symptom.causes : [];
  const completeCauses = causes.filter((cause) =>
    cause?.cause && cause?.detail && cause?.solution
  );

  return {
    id: symptom.id,
    causes: causes.length,
    complete: completeCauses.length,
    pass: causes.length >= 2 && completeCauses.length === causes.length,
  };
});

const pendingLabelChecks = [
  {
    id: 'flower-disease-render-pending',
    pass: indexHtml.includes('PENDING botanical review: ${d.treatment}'),
  },
  {
    id: 'doctor-symptom-render-pending',
    pass: indexHtml.includes('PENDING botanical review: ${c.solution}'),
  },
  {
    id: 'professional-caveat-rendered',
    pass: indexHtml.includes('This does not replace a professional diagnosis. Confirm before applying chemicals or removing plants.') &&
      indexHtml.includes('Assistive guidance only. Confirm the diagnosis before applying a treatment.'),
  },
];

const failedFlowers = flowerRows.filter((row) => !row.pass);
const failedSymptoms = symptomRows.filter((row) => !row.pass);
const failedLabels = pendingLabelChecks.filter((check) => !check.pass);
const pass = !failedFlowers.length && !failedSymptoms.length && !failedLabels.length;

console.table(flowerRows);
console.table(symptomRows);
console.table(pendingLabelChecks);
console.log(JSON.stringify({
  flowers: flowers.length,
  flowerDiseaseRows: flowerRows.reduce((total, row) => total + row.diseases, 0),
  symptoms: symptoms.length,
  symptomCauseRows: symptomRows.reduce((total, row) => total + row.causes, 0),
  failedFlowers: failedFlowers.map((row) => row.id),
  failedSymptoms: failedSymptoms.map((row) => row.id),
  failedLabels: failedLabels.map((row) => row.id),
  botanicalContentAuditReady: pass,
}, null, 2));

if (!pass) {
  process.exitCode = 1;
}
