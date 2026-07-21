import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

test('daily reminder keys use the local Mexico City date', () => {
  process.env.TZ = 'America/Mexico_City';
  const html = fs.readFileSync(new URL('../index.html', import.meta.url), 'utf8');
  const match = html.match(/function localDateKey\([\s\S]*?\n}/);
  assert.ok(match, 'index.html must define localDateKey');

  const context = { Date, result: null };
  vm.runInNewContext(
    `${match[0]}\nresult = localDateKey(new Date('2026-07-21T19:00:00-06:00'));`,
    context,
  );
  assert.equal(context.result, '2026-07-21');
});

test('watering streak compares stored ISO timestamps by local day', () => {
  process.env.TZ = 'America/Mexico_City';
  const html = fs.readFileSync(new URL('../index.html', import.meta.url), 'utf8');
  const localDateKey = html.match(/function localDateKey\([\s\S]*?^}/m);
  const getWateringStreak = html.match(/function getWateringStreak\(\) \{[\s\S]*?^}/m);
  assert.ok(localDateKey, 'index.html must define localDateKey');
  assert.ok(getWateringStreak, 'index.html must define getWateringStreak');

  const fixedNow = new Date('2026-07-21T12:00:00-06:00');
  const storedEvening = '2026-07-22T01:00:00.000Z'; // 19:00 on July 21 in Mexico City
  class FixedDate extends Date {
    constructor(...args) {
      super(...(args.length ? args : [fixedNow.getTime()]));
    }

    static now() {
      return fixedNow.getTime();
    }
  }
  const context = {
    Date: FixedDate,
    garden: [{ lastWatered: storedEvening }],
    result: null,
  };
  vm.runInNewContext(
    `${localDateKey[0]}\n${getWateringStreak[0]}\nresult = getWateringStreak();`,
    context,
  );
  assert.equal(context.result, 1);
});
