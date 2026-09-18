const CACHE = 'despachos-shell-v1';
const SHELL = ['./index.html', './manifest.json', './icons/icon-192.png', './icons/icon-512.png'];

self.addEventListener('install', ev => {
  ev.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)));
  self.skipWaiting();
});

self.addEventListener('activate', ev => {
  ev.waitUntil(
    caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
  );
  self.clients.claim();
});

// Solo el "shell" estático se cachea. Las llamadas a Supabase siempre van a la red:
// los datos de traslados/despachos deben ser siempre en vivo, nunca servidos desde caché.
self.addEventListener('fetch', ev => {
  const url = new URL(ev.request.url);
  if (url.origin !== location.origin) return; // deja pasar Supabase, fuentes, etc.
  ev.respondWith(
    caches.match(ev.request).then(hit => hit || fetch(ev.request).then(res => {
      const copy = res.clone();
      caches.open(CACHE).then(c => c.put(ev.request, copy));
      return res;
    }).catch(() => hit))
  );
});
