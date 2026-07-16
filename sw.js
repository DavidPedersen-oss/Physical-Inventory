/* Beach Property service worker — cache-first app shell for offline field use */
const CACHE = 'beachprop-v7';
const SHELL = [
  './', 'index.html', 'manifest.json', 'icon-192.png', 'icon-512.png',
  'seed/assets.json', 'seed/departments.json', 'seed/disposed.json', 'seed/users.json', 'seed/surveys.json',
  'https://cdnjs.cloudflare.com/ajax/libs/PapaParse/5.4.1/papaparse.min.js',
  'https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js'
];
self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  // never cache Power Automate sync calls or DeepSeek API traffic
  if (url.hostname.endsWith('logic.azure.com') || url.hostname.endsWith('deepseek.com') || e.request.method !== 'GET') return;
  e.respondWith(
    caches.match(e.request).then(hit => hit || fetch(e.request).then(res => {
      if (res.ok && (url.origin === location.origin || url.hostname === 'cdnjs.cloudflare.com'
          || url.hostname === 'fonts.googleapis.com' || url.hostname === 'fonts.gstatic.com')) {
        const copy = res.clone();
        caches.open(CACHE).then(c => c.put(e.request, copy));
      }
      return res;
    }))
  );
});
