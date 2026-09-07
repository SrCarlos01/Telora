/* MisFinanzas · Service Worker
   ----------------------------------------------------------------------------
   Precache de la app. El HTML de navegación se sirve NETWORK-FIRST (con la copia
   precacheada como respaldo sin conexión); el resto de los assets, CACHE-FIRST con
   revalidación en segundo plano, que es lo que permite abrir la app sin conexión.

   VERSIÓN (BUILD): el marcador __BUILD__ lo reemplaza GitHub Actions en cada
   despliegue (workflow .github/workflows/pages.yml) por el hash corto del commit.
   Como el nombre del caché deriva de BUILD, cada despliegue estrena un caché nuevo
   y 'activate' borra los anteriores. Si sw.js no cambia entre despliegues el
   navegador no detecta versión nueva: por eso el despliegue va SOLO por Actions,
   que es lo único que garantiza que BUILD se actualice sin depender de la memoria.

   Este SW NO hace skipWaiting() automático. Al desplegar una versión nueva:
     1. el navegador instala el SW nuevo y lo deja en estado "waiting";
     2. index.html detecta ese estado y muestra "Versión nueva disponible";
     3. solo cuando el usuario toca "Actualizar", index.html manda {type:'SKIP_WAITING'}
        y el SW nuevo toma el control (controllerchange -> la página se recarga sola).
   Así nadie se queda pegado en una versión vieja, pero tampoco se recarga la app
   en medio de una edición sin avisar. */

const BUILD = '__BUILD__';
const CACHE = 'misfinanzas-' + BUILD;

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
  if (!event.data) return;
  if (event.data.type === 'SKIP_WAITING') self.skipWaiting();
  // index.html pide la versión para mostrarla en el pie de Configuración.
  if (event.data.type === 'GET_BUILD' && event.source) {
    event.source.postMessage({ type: 'BUILD', build: BUILD });
  }
});

self.addEventListener('fetch', event => {
  const req = event.request;
  if (req.method !== 'GET') return;

  let url;
  try { url = new URL(req.url); } catch (_) { return; }
  if (url.origin !== self.location.origin) return;   // no tocar peticiones a terceros
  if (url.pathname.endsWith('/sw.js')) return;       // el navegador gestiona su propio script

  // --- HTML de navegación: NETWORK-FIRST ---
  // Siempre se intenta la copia fresca; si no hay red, se sirve el index
  // precacheado para que la app abra igual sin conexión.
  if (req.mode === 'navigate') {
    event.respondWith((async () => {
      const cache = await caches.open(CACHE);
      try {
        const fresh = await fetch(req);
        if (fresh && fresh.ok && fresh.type === 'basic') {
          cache.put('./index.html', fresh.clone());
        }
        return fresh;
      } catch (_) {
        const cached = await cache.match('./index.html') || await cache.match('./');
        if (cached) return cached;
        return new Response('', { status: 504, statusText: 'Sin conexión' });
      }
    })());
    return;
  }

  // --- Resto de assets: CACHE-FIRST con revalidación en segundo plano ---
  event.respondWith((async () => {
    const cache  = await caches.open(CACHE);
    const cached = await cache.match(req, { ignoreSearch: true });

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

    return new Response('', { status: 504, statusText: 'Sin conexión' });
  })());
});
