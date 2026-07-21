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

test('calendar-day strings stay on that day while complete ISO timestamps convert locally', () => {
  process.env.TZ = 'America/Mexico_City';
  const html = fs.readFileSync(new URL('../index.html', import.meta.url), 'utf8');
  const match = html.match(/function localDateKey\([\s\S]*?\n}/);
  assert.ok(match, 'index.html must define localDateKey');

  const context = { Date, calendarDay: null, instantDay: null };
  vm.runInNewContext(
    `${match[0]}\ncalendarDay = localDateKey('2026-07-21');\ninstantDay = localDateKey('2026-07-21T00:00:00.000Z');`,
    context,
  );

  assert.equal(context.calendarDay, '2026-07-21');
  assert.equal(context.instantDay, '2026-07-20');
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

test('legacy UTC notification keys never suppress the local day and v2 still shows once', () => {
  process.env.TZ = 'America/Mexico_City';
  const html = fs.readFileSync(new URL('../index.html', import.meta.url), 'utf8');
  const localDateKey = html.match(/function localDateKey\([\s\S]*?^}/m);
  const checkWateringNotifications = html.match(/function checkWateringNotifications\(\) \{[\s\S]*?^}/m);
  assert.ok(localDateKey, 'index.html must define localDateKey');
  assert.ok(checkWateringNotifications, 'index.html must define checkWateringNotifications');

  const fixedNow = new Date('2026-07-21T10:00:00-06:00');
  class FixedDate extends Date {
    constructor(...args) {
      super(...(args.length ? args : [fixedNow.getTime()]));
    }

    static now() {
      return fixedNow.getTime();
    }
  }

  const legacyKey = 'rocio_last_notification_day';
  const localDayKey = 'rocio_last_notification_local_day_v2';
  const values = new Map([[legacyKey, '2026-07-21']]);
  let notificationsShown = 0;
  const context = {
    Date: FixedDate,
    FLOWERS: [{ id: 'rosa', name: 'Rosa' }],
    Notification: { permission: 'granted' },
    ROCIO_LAST_NOTIFICATION_LEGACY_KEY: legacyKey,
    ROCIO_LAST_NOTIFICATION_LOCAL_DAY_KEY: localDayKey,
    garden: [{ flowerId: 'rosa' }],
    getUrgency: () => 'overdue',
    rocioLocalStorage: {},
    safeStorageGet: (_storage, key) => values.get(key) ?? null,
    safeStorageRemove: (_storage, key) => values.delete(key),
    safeStorageSet: (_storage, key, value) => values.set(key, value),
    showLocalPlantNotification: () => { notificationsShown += 1; },
    window: { Notification: {} },
  };

  vm.runInNewContext(`${localDateKey[0]}\n${checkWateringNotifications[0]}\ncheckWateringNotifications();`, context);
  assert.equal(notificationsShown, 1, 'the ambiguous legacy key must not suppress the local reminder');
  assert.equal(values.has(legacyKey), false, 'the obsolete UTC key should be removed');
  assert.equal(values.get(localDayKey), '2026-07-21');

  vm.runInNewContext('checkWateringNotifications();', context);
  assert.equal(notificationsShown, 1, 'the local v2 key should suppress a second reminder that day');
});
