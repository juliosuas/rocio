const ROCIO_RECOVERY_VERSION = '2026-05-27-3';

self.addEventListener('install', event => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.map(key => caches.delete(key))))
      .then(() => self.clients.claim())
      .then(() => self.clients.matchAll({ type: 'window', includeUncontrolled: true }))
      .then(clients => Promise.all(clients.map(client => {
        const url = new URL(client.url);
        if (url.searchParams.get('recovered') === ROCIO_RECOVERY_VERSION) {
          return null;
        }
        url.searchParams.set('recovered', ROCIO_RECOVERY_VERSION);
        return client.navigate(url.href).catch(() => null);
      })))
  );
});

self.addEventListener('fetch', event => {
  if (event.request.mode !== 'navigate') return;
  event.respondWith(fetch(event.request, { cache: 'reload' }));
});
