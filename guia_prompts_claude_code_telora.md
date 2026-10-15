# Guía — prompts de tanda para Claude Code (Telora) · v2

Cada regla de esta guía nace de un error o un acierto real del proyecto. La v2 conserva todo lo de la v1
y agrega la eficiencia de tokens: **el costo de una tanda depende sobre todo de lo que Code lee y de lo
que escribe, no del largo del prompt.**

---

## 0. Antes de escribir el prompt (en el chat)

- **Ambigüedad:** si el pedido tiene dos lecturas válidas, se pregunta al usuario. Code no decide
  producto (caso: «volver y saltar» del onboarding).
- **Criterio existente:** si el proyecto ya fijó una cifra o regla (p. ej. «onboarding de 90 s»), se usa
  esa y no se inventa otra.
- **Código visto, no recordado:** toda función que se nombre en el prompt se confirma antes con
  `grep` o `graphify query`. No se prometen anclas de memoria.
- **Precedente:** si ya hay una regla parecida en el código (p. ej. `hRango` bloquea el cambio de mes),
  el prompt pide replicarla.
- **Una tanda = un objetivo.** Si son dos, se hacen dos prompts y dos sesiones.

---

## 1. Plantilla (copiar y llenar; borrar las secciones que no apliquen)

```
TANDA — <nombre corto> (Día <N>, Telora)

<inicio>
git --no-optional-locks status + log --oneline -3. HEAD esperado: <hash>. Si el árbol no está limpio o el HEAD no calza: reportar y DETENERSE.
</inicio>

<contexto>
Solo lo de ESTA tanda (el contexto fijo del proyecto está en CLAUDE.md, ver §4):
- Decisiones ya cerradas (no reabrir): …
- Funciones involucradas (por nombre, nunca por número de línea): …
</contexto>

<tarea>
1. … (pasos concretos y en orden)
Si aparece otro punto del mismo tipo que no está en la lista, agrégalo y repórtalo.
Fuera de alcance: …
</tarea>

<diseño>   (solo si hay UI)
Jerarquía (principal / secundario), ubicación y componentes existentes que se reutilizan. PNG adjuntos del lienzo = fuente de verdad. 375 px sin desbordes.
</diseño>

<riesgos>
¿Crea o modifica datos reales? ¿Contadores o marcas que se duplican si se repite el paso? ¿Caso vacío? ¿Toca sync, cálculo o migración?
Si algo no calza con lo descrito: reportar y esperar, no improvisar.
</riesgos>

<detención>
Detente y pregunta antes de: SQL o esquema, tocar <módulo sensible>, agregar dependencias, borrar archivos. También si una prueba falla sin causa clara tras 2 intentos. Nunca push.
</detención>

<verificación>
- Caso normal + caso límite de la tanda, con evidencia en código (valor de estado, querySelectorAll), no «se ve bien».
- Pruebas nuevas en tests.html para lo que cambie.
- tests.html en el navegador real, 1 corrida por reloj (por defecto y ?hoy=2026-12-03), con el SW desregistrado y la caché vacía.
</verificación>

<informe>   (único, al final, sin narración intermedia)
1. Hash(es) + git diff --stat.  2. Qué se hizo (tabla corta, con archivo:línea).
3. Totales de las pruebas por reloj.  4. Desvíos y su motivo.  5. Dudas abiertas.
No pegar diffs completos salvo que la tanda toque datos, sync o cálculo (ahí sí: diff crudo).
</informe>
```

---

## 2. Eficiencia de tokens — reglas para Code

| Regla | Por qué |
|---|---|
| **Nunca leer `index.html` completo** (~1 MB). Ubicar con `grep -n` o `graphify query/explain` y leer solo rangos de líneas | Es lejos el mayor gasto de una sesión |
| **Una sesión nueva por tanda o fase.** Para seguir, cerrar la sesión y abrir otra con el prompt siguiente | El historial acumulado se vuelve a leer en cada turno |
| **Un solo informe final**, sin narrar cada paso | El texto de salida también cuesta |
| **Una corrida de pruebas por reloj.** Repetir solo si falla, y explicar el motivo | Cada corrida ocupa contexto y tiempo |
| **Diff crudo solo cuando hace falta** (datos, sync, cálculo, migraciones). En el resto, `--stat` + los fragmentos clave | Se conserva el control de la v1 donde importa |
| **Capturas a disco (scratchpad)**, no en la conversación, salvo que se pidan | Las imágenes pesan mucho en contexto |
| **Fases sin interfaz:** Code avanza solo, con commit por fase si las pruebas quedan en verde, y entrega un solo informe | Ahorra idas y vueltas (acordado el Día 23) |
| **En el chat:** pegar a Code solo el bloque del prompt; las explicaciones se quedan en el chat | El prompt corto no pierde nada, porque lo estable vive en CLAUDE.md |

---

## 3. Reglas fijas (no se negocian)

- **Método A:** el chat diagnostica y redacta; Code edita, prueba y reporta con evidencia. **Push solo
  cuando el usuario escribe «push» directamente a Code.** Para publicar una parte del historial:
  `git --no-optional-locks push origin <hash>:main`.
- **Después del push:** BUILD en `telora.cl/sw.js`, sha256 del `index.html` en producción contra
  `git show <hash>:index.html`, y la app instalada en el iPhone (cerrarla dos veces).
- **Prueba de humo manual antes de cada push.** Si el cambio toca toques, teclado o viewport, se prueba
  antes en el iPhone por la red local.
- **localStorage de pruebas:** confirmar o reiniciar el estado conocido al empezar. Motivo: «Salud»
  residual y «Débito» desincronizado (15-09).
- **Automatización de navegador:** confirmar la URL de la pestaña antes de cualquier clic o script.
  Nunca contra telora.cl salvo que sea lo declarado. Motivo: escritura de categorías en producción (13-09).
- **Cuentas de prueba:** solo en incógnito, con alias «+». Nunca la cuenta real.
- **SQL en producción:** respaldo JSON y conteos antes y después.
- **Repositorio público:** ningún correo, documento de Office, resumen ni `bases/`.

---

## 4. Contexto fijo → `CLAUDE.md` (no repetirlo en cada prompt)

Code carga `CLAUDE.md` al iniciar cada sesión, así que el «arranque en frío» de la v1 va ahí una sola
vez. El archivo es local: está en `.gitignore`. Agregar este bloque **antes** de la sección `## graphify`,
y revisarlo si se reinstala graphify:

```
## Telora — contexto fijo
- PWA comercial de finanzas personales (telora.cl). Un solo index.html, sin frameworks ni librerías externas nuevas. Español de Chile. 375 px sin desbordes.
- Sync con Supabase (9 tablas con RLS). Bandera SYNC_MULTI_ESCRITOR_ACTIVA en false salvo commit explícito; ?multi=1 solo en localhost.
- Siempre: git --no-optional-locks; nunca push sin «push» del usuario; nunca SQL ni esquema sin preguntar.
- Pruebas: tests.html en el navegador real, relojes por defecto y ?hoy=2026-12-03, con el SW desregistrado y la caché vacía.
- Eficiencia: no leer index.html completo (grep -n / graphify + rangos); un solo informe final; diff crudo solo en datos, sync o cálculo.
- Si algo no calza con lo descrito: reportar y esperar.
```

---

### Nota de método
La guía se actualiza cuando una tanda deja un patrón nuevo que conviene repetir o evitar, igual que las
lecciones de los Resúmenes del Día. Si una regla deja de servir, se borra: cada línea tiene que pagarse.
