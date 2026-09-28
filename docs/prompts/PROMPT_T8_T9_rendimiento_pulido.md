TANDA — Rendimiento y pulido: Supabase al precache, XLSX diferido, zoom accesible y tutorial con marca Telora
(Día 19, Telora)

## ARCHIVO DE TRABAJO

- Se modifican: `sw.js` (solo la lista ASSETS), `index.html` y `tutorial.html`.
- NO tocar: `privacidad.html`, `terminos.html`, `manifest.json`, `tests.html`, `.github/workflows/pages.yml`.

Primer paso obligatorio, antes de tocar nada: `git status` + `git log --oneline -5`.
HEAD esperado: `58bfce7 Comentarios: reflejan la escritura continua activa`, árbol limpio. Si algo no calza,
reporta y espera.

Segundo paso obligatorio: corre `tests.html` y reporta el resultado (esperado 135/135).

## CONTEXTO DEL PROYECTO (arranque en frío)

Telora es una PWA comercial de finanzas personales (no un proyecto personal): un único `index.html`,
sin framework ni librerías externas nuevas, desplegada en telora.cl vía GitHub Actions → GitHub Pages
(lista permitida de archivos en `_site/`). Método: tandas chicas y acotadas, diagnóstico antes de tocar
código cuando algo no es obvio, verificación con evidencia real antes de cerrar. Reglas fijas: sin
librerías externas · no cambiar nombres de archivo · español de Chile · 375 px de ancho sin desbordes ·
si algo no calza con lo descrito, reportar y esperar antes de improvisar.

## CONTEXTO DE ESTA TANDA (ya decidido, no reabrir)

Cuatro arreglos pequeños del estudio de código del Día 19, preparatorios para la venta:
- H3: `supabase.min.js` (218 KB) no está en `ASSETS` de `sw.js` (pendiente desde el Día 16): tras una
  actualización, la primera apertura sin red queda sin login ni sincronización.
- H4: `xlsx.full.min.js` (952 KB) se carga de forma síncrona en el `<head>` en CADA apertura, pero solo se
  usa al exportar a Excel. El público objetivo usa teléfonos de gama media: es costo de arranque inútil.
- H9: el viewport de `index.html` y `tutorial.html` tiene `maximum-scale=1, user-scalable=no`: bloquea el
  zoom (incumple WCAG 1.4.4 en Android).
- H8: `tutorial.html` sigue con la marca anterior "MisFinanzas" y afirma que los datos quedan «solo en tu
  teléfono», lo que ya no es cierto con el respaldo en la nube.

Descartado a propósito (NO hacer): `defer` en `supabase.min.js`. El `<script>` de "Cuenta de usuario" al
final del body evalúa `typeof supabase` en el momento del parseo; con `defer` la librería aún no existiría
y el login fallaría en silencio. Tampoco se agrega Content-Security-Policy en esta tanda.

## TAREA

### Parte A — Supabase al precache (sw.js)
1. Agrega `'./supabase.min.js'` a la lista `ASSETS` de `sw.js`. Nada más cambia en sw.js.

### Parte B — XLSX bajo demanda (index.html)
2. Quita el `<script src="./xlsx.full.min.js">` del `<head>`. Conserva (adaptado) el comentario que explica
   por qué es autohospedada y la versión 0.20.3 con sus CVE corregidas.
3. Crea una función `cargarXLSX()` que devuelva una Promise: si `window.XLSX` ya existe, resuelve de
   inmediato; si no, inserta UNA sola vez un `<script src="./xlsx.full.min.js">` (memoriza la promesa en
   curso para que dos clics seguidos no inserten dos scripts) y resuelve en `onload`; en `onerror` rechaza
   y permite reintentar (no memorices una promesa rechazada).
4. Todo punto de entrada que use `XLSX` debe esperar `cargarXLSX()` antes. Confirmados por grep:
   `exportExcel()` y el camino de compartir/descargar que llama a `buildExportWorkbook()` (el que tiene el
   fallback "descarga normal" a `exportExcel`). Busca con grep `XLSX` y cualquier otro llamador: si aparece
   un punto adicional no listado aquí, inclúyelo y repórtalo.
5. Mientras carga, el botón de exportar no debe permitir un segundo disparo (reutiliza el patrón de estado
   ocupado que ya exista en la app para botones; si no existe uno, deshabilítalo durante la espera). Si la
   carga falla, `showToast` de error en español: «No se pudo preparar la exportación. Revisa tu conexión e
   inténtalo de nuevo.»
6. Ojo con los gestos del usuario: si el camino de compartir usa `navigator.share` o `a.click()` para
   descargar, un `await` previo puede hacer que el navegador ya no lo considere un gesto del usuario y lo
   bloquee (sobre todo en iOS Safari). Diagnostica el flujo real y reporta; si hay riesgo, precarga XLSX al
   ABRIR la hoja/opción de exportación (no al tocar el botón final), de modo que al confirmar ya esté cargada.

### Parte C — Zoom accesible (index.html y tutorial.html)
7. En ambos archivos deja el viewport sin `maximum-scale` ni `user-scalable` (conserva `viewport-fit=cover`
   en index.html).
8. Riesgo iOS: al quitar `maximum-scale=1`, Safari hace zoom automático al enfocar cualquier
   `input`/`select`/`textarea` con font-size computado < 16px. Audita TODOS esos elementos visibles de la
   app (incluye los de las hojas: gasto, ingreso, meta, aporte, transferir, configuración, búsqueda del
   historial, onboarding, cierre de mes): reporta una tabla elemento → font-size computado a 375 px. Los que
   estén bajo 16px súbelos a 16px con el mismo patrón ya usado en `.export-opt input` (hay un comentario que
   lo explica). Reporta si alguno cambia visiblemente el diseño.

### Parte D — tutorial.html con marca y texto correctos
9. Reemplazos exactos:
   - `<title>`: «MisFinanzas — Cómo instalar y usar» → «Telora — Cómo instalar y usar»
   - marca: «MisFinanzas · Guía de prueba» → «Telora · Guía de prueba»
   - h1: «Bienvenida a MisFinanzas» → «Bienvenida a Telora»
   - «No necesitas crear cuenta ni dar tus datos bancarios. Todo lo que ingreses queda guardado solo en tu
     teléfono.» → «No necesitas crear cuenta ni dar tus datos bancarios. Todo lo que ingreses queda guardado
     en tu teléfono y, si inicias sesión con Google (es opcional), también puede respaldarse en la nube.»
10. `grep -n "MisFinanzas"` en tutorial.html al terminar = 0 en texto visible. Si queda alguna otra mención
   visible (no listada arriba), repórtala con su contexto antes de cambiarla.

## UBICACIÓN VISUAL / DISEÑO

- Esta tanda no agrega elementos de UI. El único cambio visible posible es el tamaño de letra de algunos
  campos (Parte C): debe mantener la jerarquía actual y seguir sin desbordes a 375 px.
- El estado "ocupado" del botón de exportar (Parte B) reutiliza el estilo existente; no inventes uno.

## RIESGOS A VERIFICAR

- Modo sin conexión: `xlsx.full.min.js` sigue en ASSETS (precacheado), así que la exportación debe funcionar
  offline después de la primera visita. Verifícalo.
- Doble clic en exportar no debe insertar dos `<script>` ni generar dos archivos.
- El login con Google no debe cambiar en nada (no se toca la carga de Supabase, solo el precache).
- Si algo de lo descrito no coincide con el código real (nombres de función, flujos), reporta y espera.

## VERIFICACIÓN (con evidencia, no "se ve bien")

Antes de verificar en el servidor local, confirma el origen de la pestaña (localhost, nunca telora.cl) y el
estado de localStorage. Desregistra el SW o usa "Update on reload" para probar el sw.js nuevo.

1. Arranque, antes y después (mismo método ambas veces): en DevTools con CPU throttling 4× y red "Fast 4G",
   recarga en frío 3 veces y reporta la mediana de `DOMContentLoaded` y de `load`
   (`performance.getEntriesByType('navigation')[0]`). Reporta también que `xlsx.full.min.js` YA NO aparece
   en la pestaña Network al abrir la app sin exportar.
2. Exportar a Excel (descarga normal): el archivo se genera y abre; en Network aparece
   `xlsx.full.min.js` una sola vez. Repetir la exportación: no vuelve a pedirse el script.
3. Doble clic rápido en exportar: `document.querySelectorAll('script[src*="xlsx"]').length === 1` y un solo
   archivo descargado.
4. Offline (servidor detenido), tras una visita previa con red: la exportación funciona.
5. Fallo simulado de carga (bloquea la URL de xlsx en DevTools → Network request blocking): aparece el toast
   de error y, al desbloquear, un segundo intento funciona.
6. Caché del SW nuevo contiene `supabase.min.js` (`caches.open(...)` → `keys()`), sin haber pasado por el login.
7. Viewport: en index.html y tutorial.html la etiqueta ya no contiene `maximum-scale` ni `user-scalable`.
   Tabla de la auditoría de font-size (Parte C) antes/después.
8. tutorial.html: `grep -c "MisFinanzas"` = 0 en texto visible; los 4 textos nuevos presentes.
9. Caso normal: tests.html sigue en 135/135.

Commits separados, en este orden: (1) sw.js: supabase.min.js al precache; (2) index.html: XLSX bajo demanda;
(3) index.html + tutorial.html: zoom accesible y campos a 16px; (4) tutorial.html: marca Telora y texto de
respaldo. NO hagas push: reporta y espera aprobación.

## INFORME FINAL (formato)

Resultado de tests.html antes y después · hashes de los 4 commits · tiempos de arranque antes/después con el
método usado · lista de puntos de entrada de XLSX encontrados (y si hubo alguno extra) · diagnóstico del gesto
del usuario en compartir/descargar y la solución elegida · tabla de font-size de campos · evidencia de cada
punto de VERIFICACIÓN · cualquier cosa que no calzó con este prompt.
