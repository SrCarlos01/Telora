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

// index.html ya no carga XLSX en el <head>: lo inserta bajo demanda con cargarXLSX()
// al abrir la hoja de exportación, pero ./xlsx.full.min.js se precachea igual para
// que exportar funcione sin conexión. ./supabase.min.js (login opcional y respaldo)
// también se precachea: tras una actualización, la primera apertura sin red conserva
// el login y la sincronización. Íconos precacheados (lo que se ve sin conexión): el de
// 192 (encabezado y notificaciones), el favicon de 32 y el apple-touch-icon; el resto
// de icons/ (512 y maskable) lo pide el sistema al instalar y no hace falta offline.
// './' e './index.html' son el mismo documento; se precachean los dos porque la
// navegación puede pedir cualquiera de las dos rutas.
const ASSETS = [
  './',
  './index.html',
  './manifest.json',
  './xlsx.full.min.js',
  './supabase.min.js',
  './icons/icon-192.png',
  './icons/favicon-32.png',
  './icons/apple-touch-icon.png'
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

// Notificación de cuota próxima a vencer: al tocarla, enfoca una pestaña de Telora ya
// abierta o abre una nueva — una notificación que no lleva a ningún lado al tocarla es
// peor que no tenerla.
self.addEventListener('notificationclick', event => {
  event.notification.close();
  const url = (event.notification.data && event.notification.data.url) || './index.html';
  event.waitUntil((async () => {
    const clientsList = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const c of clientsList) {
      if ('focus' in c) return c.focus();
    }
    if (self.clients.openWindow) return self.clients.openWindow(url);
  })());
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
  // Regla: solo la navegación a la APP (raíz del scope o index.html, con cualquier
  // query/hash, p. ej. el regreso del login OAuth) se guarda y se sirve como
  // './index.html'. Otras páginas (tutorial.html, privacidad.html, terminos.html) se
  // guardan bajo su propia URL. Corrige un bug: antes cualquier navegación se guardaba
  // como './index.html', y tras visitar el tutorial la app sin conexión abría el tutorial.
  if (req.mode === 'navigate') {
    const scopePath = new URL(self.registration.scope).pathname;
    const rel = url.pathname.startsWith(scopePath) ? url.pathname.slice(scopePath.length) : url.pathname;
    const esApp = rel === '' || rel === 'index.html';
    event.respondWith((async () => {
      const cache = await caches.open(CACHE);
      try {
        const fresh = await fetch(req);
        if (fresh && fresh.ok && fresh.type === 'basic') {
          cache.put(esApp ? './index.html' : req, fresh.clone());
        }
        return fresh;
      } catch (_) {
        if (esApp) {
          const cached = await cache.match('./index.html') || await cache.match('./');
          if (cached) return cached;
          return new Response('', { status: 504, statusText: 'Sin conexión' });
        }
        const propia = await cache.match(req);
        if (propia) return propia;
        return new Response(
          '<!DOCTYPE html><html lang="es"><head><meta charset="UTF-8">' +
          '<meta name="viewport" content="width=device-width, initial-scale=1">' +
          '<title>Sin conexión — Telora</title></head>' +
          '<body style="margin:0;padding:24px 16px;background:#161011;color:#F3E9DD;font-family:-apple-system,BlinkMacSystemFont,\'Segoe UI\',Roboto,sans-serif;">' +
          '<p>Sin conexión. Esta página necesita internet.</p>' +
          '<p><a href="./" style="color:#C9A66B;">Volver a Telora</a></p>' +
          '</body></html>',
          { status: 503, statusText: 'Sin conexión', headers: { 'Content-Type': 'text/html; charset=utf-8' } }
        );
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
