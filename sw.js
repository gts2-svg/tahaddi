const CACHE = 'tahaddi-v1.1.1';
const CORE = ['./', 'index.html', 'style.css', 'app.js', 'manifest.json',
  'data/religion.txt', 'data/seerah.txt', 'data/history.txt', 'data/geography.txt', 'data/poetry.txt',
  'data/arabic.txt', 'data/saudi.txt', 'data/whoami.txt',
  'icons/icon-192.png', 'icons/icon-512.png', 'icons/icon-180.png'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(CORE)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
// الشبكة أولاً للملفات المحلية (لتصل التحديثات)، والكاش عند انقطاع النت
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET') return;
  if (url.origin === location.origin) {
    e.respondWith(fetch(e.request).then(r => {
      const copy = r.clone(); caches.open(CACHE).then(c => c.put(e.request, copy)); return r;
    }).catch(() => caches.match(e.request, { ignoreSearch: true })));
  } else if (/fonts\.(googleapis|gstatic)\.com/.test(url.host)) {
    e.respondWith(caches.match(e.request).then(m => m || fetch(e.request).then(r => {
      const copy = r.clone(); caches.open(CACHE).then(c => c.put(e.request, copy)); return r;
    })));
  }
});
