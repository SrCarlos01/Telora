/* MisFinanzas · Service Worker (Tanda Q · pto 6)
   ----------------------------------------------------------------------------
   Precache de la app + estrategia cache-first con revalidación en segundo plano.

   El caché está VERSIONADO (CACHE). Para invalidarlo en un despliegue futuro basta
   con subir el número de versión: en 'activate' se borran todos los cachés cuyo
   nombre no coincida con el actual.

   Este SW NO hace skipWaiting() automático. Cuando se despliega una versión nueva:
     1. el navegador instala el SW nuevo y lo deja en estado "waiting";
     2. index.html detecta ese estado y muestra el aviso "Versión nueva disponible";
     3. solo cuando el usuario toca "Actualizar", index.html manda {type:'SKIP_WAITING'}
        y el SW nuevo toma el control (controllerchange -> la página se recarga sola).
   Así nadie se queda pegado en una versión vieja "para siempre", pero tampoco se
   recarga la app en medio de una edición sin avisar. */

const CACHE = 'misfinanzas-v1';

// index.html carga XLSX desde ./xlsx.full.min.js y el ícono desde ./icon.svg.
// './' e './index.html' son el mismo documento; se precachean los dos porque la
// navegación puede pedir cualquiera de las dos rutas.
const ASSETS = [
  './',
  './index.html',
  './manifest.json',
  './xlsx.full.min.js',
  './icon.svg'
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE).then(c => c.addAll(ASSETS)).catch(() => {})
  );
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)));
    await self.clients.claim();
  })());
});

self.addEventListener('message', event => {
  if (event.data && event.data.type === 'SKIP_WAITING') self.skipWaiting();
});

self.addEventListener('fetch', event => {
  const req = event.request;
  if (req.method !== 'GET') return;

  let url;
  try { url = new URL(req.url); } catch (_) { return; }
  if (url.origin !== self.location.origin) return;   // no tocar peticiones a terceros

  event.respondWith((async () => {
    const cache  = await caches.open(CACHE);
    const cached = await cache.match(req, { ignoreSearch: true });

    // Revalidación en segundo plano: si hay red, refresca la copia en caché.
    const network = fetch(req).then(res => {
      if (res && res.ok && res.type === 'basic') cache.put(req, res.clone());
      return res;
    }).catch(() => null);

    if (cached) {
      event.waitUntil(network);   // no bloquea la respuesta
      return cached;
    }

    const fresh = await network;
    if (fresh) return fresh;

    // Sin caché y sin red: para una navegación, servir el index precacheado.
    if (req.mode === 'navigate') {
      const fallback = await cache.match('./index.html');
      if (fallback) return fallback;
    }
    return new Response('', { status: 504, statusText: 'Sin conexión' });
  })());
});
