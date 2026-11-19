/* تحدّي — ملف التخزين المؤقت (يعمل التطبيق بلا إنترنت بعد أول فتح).
   رقم الإصدار يأتي من app.js نفسه: يُسجَّل الملف بعنوان sw.js?v=<VERSION>، فلا يُكتب الرقم إلا في مكان واحد.
   قائمة ملفات الأسئلة تُقرأ من data/cats.json، فإضافة قسم لا تحتاج تعديل هذا الملف. */
const VERSION = new URL(self.location.href).searchParams.get('v') || 'dev';
const CACHE = 'tahaddi-v' + VERSION;
const TIMEOUT = 3000; // مهلة الشبكة قبل الرجوع إلى المحفوظ
// صور الأقسام من Unsplash: لها مخزن مستقل لا يُمسح مع كل إصدار، والمحفوظ أولاً (الصورة لا تتغير)
const PHOTOS = 'photos-tahaddi-1';
const PHOTO_HOST = 'images.unsplash.com';
const CORE = ['./', 'index.html', 'style.css', 'fonts.css', 'logic.js', 'app.js', 'manifest.json', 'data/cats.json',
  'icons/icon-192.png', 'icons/icon-512.png', 'icons/icon-180.png',
  'fonts/amiri-arabic-400-normal.woff2', 'fonts/amiri-arabic-700-normal.woff2', 'fonts/amiri-latin-400-normal.woff2', 'fonts/amiri-latin-700-normal.woff2',
  'fonts/readex-pro-arabic-400-normal.woff2', 'fonts/readex-pro-arabic-500-normal.woff2', 'fonts/readex-pro-arabic-600-normal.woff2', 'fonts/readex-pro-arabic-700-normal.woff2',
  'fonts/readex-pro-latin-400-normal.woff2', 'fonts/readex-pro-latin-500-normal.woff2', 'fonts/readex-pro-latin-600-normal.woff2', 'fonts/readex-pro-latin-700-normal.woff2'];

// مفتاح الحفظ بلا لاحقة ?v= حتى تُستبدل النسخة القديمة بالجديدة دائماً
const keyOf = req => { const u = new URL(req.url || req, self.location.href); u.search = ''; u.hash = ''; return u.href; };

async function precache() {
  const c = await caches.open(CACHE);
  let files = [];
  try {
    const r = await fetch('data/cats.json', { cache: 'no-cache' });
    if (r.ok) files = ((await r.clone().json()).categories || []).map(x => x.file).filter(Boolean);
  } catch {}
  await Promise.all([...CORE, ...files].map(async f => {
    try {
      const r = await fetch(f, { cache: 'no-cache' });
      if (r.ok) await c.put(keyOf(f), r);
    } catch {}
  }));
}
self.addEventListener('install', e => { e.waitUntil(precache().then(() => self.skipWaiting())); });
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k.startsWith('tahaddi-') && k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});

// الشبكة أولاً (لتصل التحديثات وتعديلات الأسئلة)، فإن تأخرت أكثر من 3 ثوانٍ أو انقطعت فالمحفوظ.
// لا يُحفظ إلا الرد السليم (ok)، فرد «غير موجود» لا يطغى على نسخة صحيحة.
self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.hostname === PHOTO_HOST) {
    e.respondWith((async () => {
      const c = await caches.open(PHOTOS);
      const hit = await c.match(req, { ignoreVary: true });
      if (hit) return hit;
      try { const r = await fetch(req); if (r && (r.ok || r.type === 'opaque')) await c.put(req, r.clone()); return r; }
      catch { return Response.error(); }
    })());
    return;
  }
  if (url.origin !== self.location.origin) return;
  e.respondWith((async () => {
    const key = keyOf(req);
    const net = fetch(req).then(async r => {
      if (r && r.ok && r.type === 'basic') { const c = await caches.open(CACHE); await c.put(key, r.clone()); }
      return r;
    });
    const timeout = new Promise(res => setTimeout(() => res(null), TIMEOUT));
    let r = null;
    try { r = await Promise.race([net, timeout]); } catch { r = null; }
    if (r && r.ok) return r;
    const cached = await caches.match(key) || await caches.match(req, { ignoreSearch: true });
    if (cached) { e.waitUntil(net.catch(() => {})); return cached; }
    if (r) return r;            // رد غير سليم ولا نسخة محفوظة: نعيده كما هو
    return net;                 // لا محفوظ: ننتظر الشبكة مهما طالت
  })());
});
