// =====================================================================
// NEXUS · Service Worker compartido
// =====================================================================
// Hace dos cosas:
// 1. Deja que la página se instale como app y se abra sin conexión
//    (en vez de pantalla de error, se ve la última versión guardada).
// 2. Guarda también las respuestas de Supabase (lecturas) según van
//    llegando — así si falla la red a medio uso, se sigue viendo la
//    última carta/datos que sí llegaron a cargar bien.
//
// Lo que NO hace, porque no puede: traer datos nuevos sin conexión.
// Eso es física, no ingeniería — sin red no hay forma de saber si algo
// cambió en el servidor.
// =====================================================================

const CACHE_NAME = 'nexus-cache-v1';

self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then(names =>
      Promise.all(names.filter(n => n !== CACHE_NAME).map(n => caches.delete(n)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return; // nunca cachear escrituras (insert/update/delete)

  event.respondWith(
    fetch(event.request)
      .then((response) => {
        // guarda una copia de cada respuesta buena para poder usarla si luego falla la red
        if (response && response.status === 200){
          const copia = response.clone();
          caches.open(CACHE_NAME).then(cache => cache.put(event.request, copia));
        }
        return response;
      })
      .catch(() => caches.match(event.request))
  );
});
