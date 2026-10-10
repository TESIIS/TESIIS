/* Generated resource list is produced by `dart run tool/prepare_web.dart`. */
importScripts('offline-manifest.js');
const manifest = self.TESIIS_MANIFEST;
const cacheName = `tesiis-shell-${manifest.version}`;
const base = new URL('./', self.location.href);
const resources = new Set(manifest.files.map((file) => new URL(file, base).href));
const indexUrl = new URL('index.html', base).href;

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(cacheName);
    try {
      // Bounded parallelism; installation is all-or-nothing. A failed update
      // leaves the previous active worker and its complete cache intact.
      const files = [...resources];
      for (let i = 0; i < files.length; i += 4) {
        await cache.addAll(files.slice(i, i + 4).map((url) => new Request(url, {cache: 'reload'})));
      }
    } catch (error) { await caches.delete(cacheName); throw error; }
  })());
});
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const name of await caches.keys()) {
      if (name.startsWith('tesiis-shell-') && name !== cacheName) await caches.delete(name);
    }
    await self.clients.claim();
  })());
});
self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== base.origin || !url.pathname.startsWith(base.pathname)) return;
  // Neither API responses nor external map tiles are cached by this worker.
  const key = request.mode === 'navigate' ? indexUrl : url.origin + url.pathname;
  if (!resources.has(key)) return;
  event.respondWith((async () => {
    const cache = await caches.open(cacheName);
    return (await cache.match(key)) ?? fetch(request);
  })());
});
self.addEventListener('message', (event) => {
  if (event.data?.type === 'ACTIVATE') event.waitUntil(self.skipWaiting());
  if (event.data?.type === 'STATUS') event.waitUntil((async () => {
    const cache = await caches.open(cacheName);
    const keys = new Set((await cache.keys()).map((r) => r.url));
    event.ports[0]?.postMessage({ready: [...resources].every((url) => keys.has(url)), version: manifest.version, bytes: manifest.bytes});
  })());
});
