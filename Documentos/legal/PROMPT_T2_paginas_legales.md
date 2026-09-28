TANDA — Páginas legales (Privacidad y Términos) + texto veraz en "Cuenta de usuario"
(Día 19, Telora)

## ARCHIVO DE TRABAJO

- Archivos NUEVOS en la raíz del repo: `privacidad.html` y `terminos.html`.
- Archivo existente a modificar: `index.html` (solo los puntos de la sección TAREA, parte B).
- Fuentes del contenido (NO se publican, solo se leen): `Documentos/legal/privacidad.md` y `Documentos/legal/terminos.md`.
- También se modifica `.github/workflows/pages.yml` (solo la Parte D).
- NO tocar: `tutorial.html`, `sw.js`, `tests.html`, `manifest.json`.

Primer paso obligatorio, antes de tocar nada: `git status` + `git log --oneline -5`.
HEAD esperado: `c78a87a Fechas de registro en hora local, no UTC ...`, árbol limpio salvo la carpeta `Documentos/legal/`
(nueva, sin seguimiento, con 2 .md y este prompt). Inclúyela en el commit (1). Si algo no calza, reporta y espera.

Segundo paso obligatorio: abre `tests.html` en el servidor local y reporta el resultado (esperado 135/135).
El commit c78a87a (reemplazo de `toISOString().slice(0,10)` por `fechaHoyLocalISO()` en 16 sitios + 2
ajustes) se hizo sin pasar por la suite; esta corrida lo valida. Si algo falla, reporta y espera.

## CONTEXTO DEL PROYECTO (arranque en frío)

Telora es una PWA comercial de finanzas personales (no un proyecto personal): un único `index.html`,
sin framework ni librerías externas nuevas, desplegada en telora.cl vía GitHub Actions → GitHub Pages.
Método: tandas chicas y acotadas, diagnóstico antes de tocar código cuando algo no es obvio, verificación
con evidencia real antes de cerrar. Reglas fijas: sin librerías externas · no cambiar nombres de archivo
existentes · español de Chile · 375 px de ancho sin desbordes · si algo no calza con lo descrito,
reportar y esperar antes de improvisar.

## CONTEXTO DE ESTA TANDA (ya decidido, no reabrir)

- Telora necesita Política de Privacidad y Términos de Uso publicados antes de venderse: los exigen Google
  Play, App Store y la verificación de marca de Google OAuth, y la Ley 21.719 entra en vigencia el
  1-dic-2026.
- Decidido: páginas estáticas `privacidad.html` y `terminos.html` en la raíz, servidas en
  telora.cl/privacidad.html y telora.cl/terminos.html. Responsable: persona natural. Edad mínima 18.
  Contacto privacidad@telora.cl.
- El TEXTO LEGAL ya está redactado y revisado en los .md. Tu trabajo es convertirlo a HTML con fidelidad,
  no reescribirlo. No cambies, resumas ni "mejores" ninguna frase. Si ves algo que te parece un error de
  contenido, repórtalo en el informe final, no lo corrijas.
- Desde el commit 4ef6696 la escritura continua a la nube está ACTIVA (ESCRITURA_CONTINUA_ACTIVA = true).
  Por eso el texto actual del bloque "Cuenta de usuario" en Configuración ("por ahora siguen guardados solo
  en este dispositivo") es FALSO y hay que corregirlo en esta tanda.

## TAREA

### Parte A — Páginas legales

1. Marcadores: el único permitido en los .md es `[FECHA DE PUBLICACIÓN]` (línea "Vigente/Vigentes desde").
   En el HTML reemplázalo por la fecha del día en que creas las páginas, en formato "28 de septiembre de
   2026" — es la ÚNICA sustitución de contenido autorizada. Si encuentras cualquier otro texto entre
   corchetes (por ejemplo `[COMUNA]`), DETENTE y reporta: no lo inventes.
2. Crea `privacidad.html` y `terminos.html` convirtiendo el markdown a HTML semántico a mano (h1, h2, p,
   ul/li, table con thead/tbody, strong, a). Sin librería de markdown.
3. Estilo: el mismo lenguaje visual de la app, tomando como referencia `tutorial.html` (página estática
   existente del proyecto): mismos tokens de color (fondo oscuro, crema, dorado), tipografía serif en
   títulos y sans en cuerpo. CSS inline en un `<style>` propio de cada página, sin archivos nuevos.
4. Cada página debe tener: `<html lang="es">`, charset, viewport (SIN `maximum-scale` ni
   `user-scalable=no`), `<title>` ("Política de Privacidad — Telora" / "Términos de Uso — Telora"),
   `<meta name="description">`, `<link rel="icon" href="icon.svg">`, `theme-color` igual al de index.html.
5. Arriba de cada página: enlace discreto "← Volver a Telora" que apunta a `./`. Al pie: enlace cruzado a
   la otra página legal.
6. Las tablas deben caber en 375 px: si una tabla no cabe, envuélvela en un contenedor con scroll
   horizontal propio (`overflow-x:auto`), nunca desbordar la página completa.
7. El enlace "Política de Privacidad" que aparece dentro de terminos.md debe apuntar a `privacidad.html`.

### Parte B — Cambios en index.html

8. Bloque "Cuenta de usuario", estado SIN sesión (`#cuentaUsuarioSinSesion`): reemplaza el párrafo actual por:
   «Inicia sesión con tu cuenta de Google para respaldar tus datos en la nube. Es opcional: sin iniciar
   sesión, tus datos se guardan solo en este dispositivo.»
   Debajo del botón "Continuar con Google", agrega una nota pequeña:
   «Al continuar aceptas los Términos de Uso y la Política de Privacidad.» con ambos nombres como enlaces
   a `terminos.html` y `privacidad.html`, `target="_blank" rel="noopener"`.
9. Pie de Configuración: junto a la línea de versión existente (`#cfgBuildInfo`, "Telora · versión …"),
   agrega una línea con "Privacidad · Términos" como enlaces (mismos atributos que el punto 8). Jerarquía
   visual: elemento DISCRETO, mismo tamaño y opacidad que la línea de versión; no es un botón.
10. Busca con grep cualquier OTRO texto visible para el usuario en index.html que afirme que los datos
   están "solo en este dispositivo", "no se sincroniza", "pronto podrás respaldar" o similar, y que ya no
   sea cierto con la escritura continua activa. NO los cambies: lístalos en el informe con su contexto
   (función o sección), para decidir en el chat de planificación.

### Parte C — Solo diagnóstico, sin cambios

11. Estado CON sesión (`#cuentaUsuarioConSesion`): hoy solo muestra el correo. Queremos, en una tanda
   posterior, una línea que diga si ESTE dispositivo está respaldando o no (solo el dispositivo escritor
   escribe; ver `syncHabilitada()`, `syncCtx.esEscritor` y el sheet de legado). Reporta qué estado confiable
   existe en el código para saberlo en el momento de pintar `renderCuentaUsuario()`, y en qué casos
   podría estar indefinido (ej. antes de que termine la evaluación del escritor). No implementes nada.

### Parte D — Publicar solo lo que corresponde (hallazgo de seguridad, prioridad alta)

Hallazgo verificado el 27-09-2026: el workflow sube el árbol completo (`path: .`) y solo quita
`tests.html`. Por eso hoy son públicos en telora.cl los resúmenes internos (`/Documentos/*.docx`),
`/Bases/*.docx` y `/guia_prompts_claude_code_telora.md` (confirmado: se descargan).

12. Cambia el workflow de "publicar todo menos X" a una LISTA PERMITIDA: un paso que cree un directorio
   `_site/`, copie en él SOLO los archivos que el sitio necesita y suba `_site` como artefacto. Antes de
   escribir la lista, obtenla del código, no de memoria: todo lo que referencian `index.html`,
   `sw.js` (ASSETS), `manifest.json`, `tutorial.html` y las dos páginas legales nuevas (scripts, ícono,
   manifest, enlaces internos). Esperado, a confirmar: index.html, sw.js, manifest.json, icon.svg,
   xlsx.full.min.js, supabase.min.js, tutorial.html, privacidad.html, terminos.html. Si aparece un archivo
   referenciado que no está en esta lista esperada, agrégalo y repórtalo. Si existe un archivo `CNAME` en
   la raíz, debe ir incluido (el dominio telora.cl depende de él); repórtalo en cualquier caso.
13. El estampado de BUILD en sw.js debe seguir ocurriendo, y debe aplicarse al sw.js que efectivamente se
   publica (el de `_site/`). Elimina el paso "Excluir tests.html", que ya no hace falta, y deja un
   comentario que explique la lista permitida y por qué (este hallazgo).
14. Verificación local del workflow (sin push): ejecuta los mismos comandos de copia en una carpeta
   temporal y lista su contenido; confirma que no hay .docx, .md, carpetas Documentos/ ni Bases/, ni
   tests.html. Después del push (cuando se apruebe) se verificará en producción que
   telora.cl/Documentos/Dia18_Resumen.docx y telora.cl/guia_prompts_claude_code_telora.md devuelven 404
   y que la app, el tutorial y las páginas legales cargan.

Fuera de esta tanda: botón "Eliminar mi cuenta" (tanda aparte), landing (T4), cualquier cambio en sw.js.

## RIESGOS A VERIFICAR

- Service worker: `sw.js` sirve el HTML de navegación con network-first y copia precacheada de respaldo.
  Revisa (sin modificarlo) qué responde el SW a una navegación a `privacidad.html`, que NO está en ASSETS:
  con red y SIN red. Si sin red devolvería `index.html` u otra cosa engañosa en vez de fallar, repórtalo.
- En la PWA instalada (modo standalone), un enlace sin `target="_blank"` sacaría al usuario de la app sin
  forma de volver. Por eso el target es obligatorio en los enlaces del punto 8 y 9.
- El pie de Configuración y el bloque de cuenta ya tienen estilos: reutiliza las clases existentes
  (`sheet-note`, etc.) en vez de crear estilos paralelos.
- Si algo de lo descrito no coincide con el código real (ids, textos, estructura), reporta y espera.

## VERIFICACIÓN (con evidencia, no "se ve bien")

Antes de verificar en el servidor local, confirma el origen de la pestaña (localhost, nunca telora.cl) y el
estado de localStorage.

1. `privacidad.html` y `terminos.html` a 375 px: `document.documentElement.scrollWidth <= 375` en ambas.
2. Fidelidad: número de `<h2>` en cada HTML = número de `##` en su .md (13 y 13). Reporta ambos conteos.
   Además, compara el texto plano de cada HTML contra su .md (sin marcas de formato) y reporta cualquier
   diferencia de palabras.
3. `grep -c "MisFinanzas"` en los dos HTML nuevos = 0.
4. En index.html, Configuración sin sesión: el párrafo nuevo se ve; los enlaces existen
   (`querySelectorAll('a[href="privacidad.html"]').length` y `a[href="terminos.html"]` ≥ 2 cada uno, con
   target _blank). Clic real en cada enlace → abre la página correcta.
5. Pie de Configuración a 375 px sin desborde ni superposición.
6. Caso normal: tests.html sigue en 135/135 después de los cambios.
7. Reporta el resultado del punto 10 (textos desactualizados) y de la Parte C (diagnóstico).

Commits separados: (1) páginas legales nuevas; (2) cambios en index.html; (3) workflow con lista permitida. NO hagas push: reporta y espera
aprobación.
