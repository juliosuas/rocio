const LEGACY_CACHE_PREFIX = 'rocio-shell';

self.addEventListener('install', event => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(key => key.startsWith(LEGACY_CACHE_PREFIX)).map(key => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', () => {
  // Online-first: do not intercept requests.
});
