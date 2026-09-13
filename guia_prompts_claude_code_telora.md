# Guía de referencia — cómo armar un prompt de tanda para Claude Code (Telora)

Plantilla a seguir cada vez que se prepare un prompt de tanda, basada en el
patrón que ya ha funcionado (T6, botón "Ir a hoy", botón "Volver" del
onboarding). El objetivo no es rellenar secciones por rellenarlas: cada una
existe porque resolvió un problema real que ya ocurrió en este proyecto.

---

## 0. Antes de escribir el prompt — checklist propio

- ¿Hay algo ambiguo en el pedido que, si lo asumo mal, hace que el prompt
  resuelva el problema equivocado? Si sí, **preguntar antes de escribir el
  prompt**, no dejar que Claude Code decida por su cuenta un punto de
  diseño/producto. (Ejemplo real: "volver y saltar" del onboarding tenía dos
  lecturas válidas y muy distintas.)
- ¿El pedido tiene una motivación de negocio o de retención documentada en
  algún resumen anterior? Si existe una cifra o un criterio ya establecido
  por el propio proyecto (ej. "onboarding de 90 segundos"), usarlo en vez de
  inventar uno nuevo — da al prompt una base real, no una opinión.
- ¿Voy a tocar una función que ya reviso en el código, o estoy asumiendo su
  comportamiento de memoria? Si no la he visto, revisarla (grep, sed -n)
  antes de prometer un ancla o una regla en el prompt.
- ¿El cambio interactúa con algo que ya tiene una regla explícita en el
  código (ej. `hRango` bloqueando la navegación de mes)? Si existe un
  precedente, el prompt debe pedir que se replique ese mismo criterio, no
  que se invente uno nuevo y potencialmente inconsistente.

---

## 1. Encabezado

```
TANDA — <nombre corto y descriptivo de la tanda>
(Día <N>, Telora)
```

## 2. ARCHIVO DE TRABAJO

- Nombrar el archivo exacto sobre el que se trabaja (`index.html`, salvo que
  la tanda diga explícitamente otra cosa) y su ubicación (raíz del repo).
- Aclarar qué NO se toca si hay riesgo de confusión (ej. `tutorial.html` es
  un artefacto aparte).
- Pedir siempre, como primer paso, `git status` + `git log --oneline -5`
  para confirmar árbol limpio y HEAD esperado **antes de tocar nada** — y
  que reporte y espere si algo no calza (working tree sucio, HEAD
  inesperado). Esto no es opcional: ya salvó una pieza de trabajo completa
  (el onboarding) que llevaba un día entero sin commitear.

## 3. CONTEXTO DEL PROYECTO (arranque en frío)

Un chat nuevo de Claude Code no tiene memoria de nada de lo discutido en
este chat. Incluir siempre, en una versión breve y estable:

- Qué es Telora (PWA de finanzas personales, producto comercial, no
  personal), sin framework ni librerías externas, un único `index.html`,
  375 px de ancho sin desbordes.
- El método de trabajo del proyecto: tandas chicas y acotadas, diagnóstico
  antes de tocar código cuando algo no es obvio, verificación con evidencia
  real (no "se ve bien") antes de cerrar.
- Las reglas fijas: sin librerías externas · no cambiar el nombre del
  archivo · español de Chile · 375 px sin desbordes · si algo no calza con
  lo descrito, reportar y esperar antes de improvisar.

## 4. CONTEXTO DE ESTA TANDA (lo ya discutido y cerrado)

- Resumir la especificación ya acordada en la conversación previa, dejando
  explícito qué **no** hay que redefinir ni reabrir como decisión de
  producto — esa discusión ya se tuvo, el prompt es para ejecutar, no para
  volver a decidir el alcance.
- Si el cambio depende de código existente, dar el nombre real de la(s)
  función(es) involucradas (confirmadas por grep/lectura propia), nunca
  números de línea como referencia principal — las líneas se mueven de una
  sesión a otra.

## 5. TAREA

- Pasos numerados, concretos, en el orden en que hay que hacerlos.
- Cuando la tarea tenga una lista de puntos de aplicación (ej. "aplicar X en
  estas 10 funciones"), enumerarlos por función/contexto, no por línea, y
  pedir explícitamente que si aparece un punto adicional del mismo tipo no
  listado, lo agregue y lo reporte — la lista armada a mano rara vez es
  exhaustiva (T6: la auditoría manual encontró menos de la mitad de los
  puntos reales).
- Marcar con claridad qué queda **fuera** de la tanda, si hay algo cercano
  que podría confundirse con parte del alcance.

## 6. UBICACIÓN VISUAL / DISEÑO (cuando aplique)

- Si el cambio agrega un elemento de UI, especificar su jerarquía visual
  relativa (¿es un botón principal o un elemento discreto/secundario?) y
  dónde va, no solo qué hace — dejar esto abierto produce resultados
  genéricos o que no calzan con el estilo ya establecido.
- Recordar siempre la restricción de 375 px y pedir verificación explícita
  de que no se desborda ni se superpone con otros elementos.

## 7. RIESGOS A VERIFICAR — lo que no hay que dar por sentado

Esta es la sección que más ha evitado errores reales. Antes de asumir que un
cambio es "solo de navegación" o "solo visual", pensar si toca:

- Código que **crea o modifica datos reales** (no solo estado de UI) — un
  botón que parece de navegación puede estar detrás de una acción que
  guarda un registro (ej. el Paso 4 del onboarding, que crea gastos fijos
  reales al continuar).
- Un caso ya resuelto en otra parte del código con una regla explícita (ej.
  `hRango` bloqueando `prevMonth`/`nextMonth`) — pedir que se replique ese
  criterio, no que se invente uno paralelo.
- Contadores, estados acumulados o flags que podrían resetearse o
  duplicarse si el usuario repite un paso o una acción (ej. contadores del
  onboarding, marcas de "ya visto").
- Casos sin datos / vacíos — qué debe pasar si lo que se busca (un día, una
  fila, un registro) simplemente no existe.
- Pedir explícitamente: si algo de esto no está claro en el código o el
  comportamiento no es el esperado, **reportarlo y esperar**, no resolverlo
  en silencio con la primera solución razonable.

## 8. VERIFICACIÓN

- Nunca aceptar "funciona" sin un método de verificación explícito y
  reproducible: con qué dato de prueba, en qué pantalla, y qué resultado
  concreto confirma que funcionó (idealmente algo verificable en código —
  un `querySelectorAll`, un valor de estado — no solo una inspección
  visual).
- Incluir siempre el caso normal (sin cambios, ¿se rompió algo?) y el caso
  límite específico de la tanda.
- Si la tanda toca algo que ya causó bugs reales en el proyecto (motor de
  cálculo, migraciones, datos de usuario), pedir la verificación con un
  caso concreto y no solo con el reporte de éxito de Claude Code.

---

### Nota de método

Esta guía se arma sobre la base de errores y aciertos reales de este
proyecto — no es una plantilla genérica de buenas prácticas. Si en una
tanda futura aparece un patrón nuevo que valga la pena repetir o evitar,
esta guía debería actualizarse con ese aprendizaje, de la misma forma en
que los Resúmenes del Día ya documentan notas de método por separado.
