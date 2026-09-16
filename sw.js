// Service Worker del Buscador de Contenedores SPB.
// Guarda una copia de la app (HTML/íconos) para que abra rápido y funcione
// aunque no haya internet en el momento — los DATOS (contenedores/agencias)
// siempre requieren conexión para sincronizarse, pero la última búsqueda
// hecha se puede seguir viendo sin conexión porque queda en memoria del
// propio navegador mientras la pestaña sigue abierta.
const CACHE_NAME = 'spb-buscador-v1';
const ARCHIVOS_APP = [
    './index.html',
    './manifest.json',
    './icon-192.png',
    './icon-512.png',
    './icon-512-maskable.png'
];

self.addEventListener('install', (event) => {
    event.waitUntil(
        caches.open(CACHE_NAME).then((cache) => cache.addAll(ARCHIVOS_APP))
    );
    self.skipWaiting();
});

self.addEventListener('activate', (event) => {
    event.waitUntil(
        caches.keys().then((nombres) =>
            Promise.all(nombres.filter((n) => n !== CACHE_NAME).map((n) => caches.delete(n)))
        )
    );
    self.clients.claim();
});

self.addEventListener('fetch', (event) => {
    // Las llamadas a Supabase (datos reales) NUNCA se sirven desde caché — siempre
    // deben ir a la red, para no mostrar información vieja como si fuera actual.
    if (event.request.url.includes('supabase.co')) return;

    event.respondWith(
        caches.match(event.request).then((respuestaCache) => {
            return respuestaCache || fetch(event.request);
        })
    );
});
