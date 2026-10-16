/* Edge Function «eliminar-cuenta» (Telora · T2b)
   ------------------------------------------------------------------------------------------
   REQUISITOS DE DESPLIEGUE (no omitir):
     1. «Verify JWT with legacy secret» = OFF; la autenticación se hace aquí. El proyecto ya
        no usa el secreto JWT legacy, así que el gateway no verifica nada: esta función valida
        el usuario con auth.getUser(jwt) y, en el caso idempotente (usuario ya inexistente),
        verifica la firma del token con auth.getClaims (JWKS del proyecto) antes de usar su sub.
     2. Usa SUPABASE_URL y la clave secreta que Supabase inyecta por defecto en toda Edge
        Function: primero SUPABASE_SECRET_KEYS (diccionario JSON; la clave "default" o, si no
        existe, la primera) y, solo como respaldo, SUPABASE_SERVICE_ROLE_KEY (variable legacy).
        No se crea ningún secret a mano y la clave secreta NUNCA va al cliente ni al repositorio.

   Qué hace (solo POST; el uid sale SOLO del JWT, jamás del cuerpo de la petición):
     1. Obtiene el usuario con el JWT del header Authorization. Sin JWT válido -> 401.
        Reautenticación (S2): el JWT debe venir de un inicio de sesión de hace como mucho 10 min
        (claims.amr). Si no -> 401 { error: "reauth_required" }, ANTES de cualquier borrado.
     2. auth.admin.deleteUser(uid, false): borrado real (no soft delete). Las 9 tablas tienen
        FK user_id -> auth.users(id) ON DELETE CASCADE, así que sus filas se van con el usuario
        y, desde ese instante, ningún insert con ese user_id puede volver a entrar (23503).
     3. Verifica con la clave secreta que las 9 tablas quedaron en 0 filas para ese uid. Si
        alguna tuviera filas, las borra explícitamente (goal_aportes antes que goals) y lo informa.
   Idempotente: si el usuario ya no existe en auth (y la firma del token es válida), solo
   verifica 0 filas y responde ok.
   Respuesta: { ok, verificacion: { tabla: 0, ... }, borradasExplicitas?: { tabla: n } }.
   Logs sin datos personales: solo el uid truncado. */

// Versión exacta: la misma del cliente (supabase.min.js). Al actualizar uno, actualizar el otro.
import { createClient } from "npm:@supabase/supabase-js@2.117.1";

// S2: ventana de reautenticación (segundos) para eliminar la cuenta.
const VENTANA_REAUTH_SEG = 600;

// Orden hijo -> padre para un borrado explícito: goal_aportes antes que goals.
const TABLAS = [
  "goal_aportes", "goals", "cuentas_financieras", "transfers", "expenses",
  "incomes", "debts", "config_compartida", "config_dispositivo",
];

const ORIGEN_PRODUCCION = "https://telora.cl";
const ORIGEN_LOCAL = /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/;

function origenPermitido(origen: string | null): boolean {
  return !!origen && (origen === ORIGEN_PRODUCCION || ORIGEN_LOCAL.test(origen));
}

function cabecerasCors(origen: string | null): Record<string, string> {
  const h: Record<string, string> = {
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  };
  if (origenPermitido(origen)) h["Access-Control-Allow-Origin"] = origen as string;
  return h;
}

function responder(origen: string | null, status: number, cuerpo: unknown): Response {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: { ...cabecerasCors(origen), "Content-Type": "application/json; charset=utf-8" },
  });
}

const uidCorto = (uid: string) => uid.slice(0, 8) + "…";

// <puro> — Lógica pura sin Deno ni red. tests.html extrae este bloque, le quita las
// anotaciones de tipo de los parámetros (solo «nombre: tipo» simples, sin tipo de retorno)
// y lo prueba en el navegador. Mantenerlo así.

// Clave secreta a partir de SUPABASE_SECRET_KEYS ({"default": "sb_secret_…", …}) y, como
// respaldo, SUPABASE_SERVICE_ROLE_KEY (legacy). -> { clave, fuente, invalido }: clave "" y
// fuente "ninguna" si no hay ninguna; invalido = SUPABASE_SECRET_KEYS no era JSON.
function elegirClaveSecreta(dicTexto: string, legacy: string) {
  let invalido = false;
  if (dicTexto) {
    try {
      const o = JSON.parse(dicTexto);
      if (o && typeof o === "object" && !Array.isArray(o)) {
        if (typeof o.default === "string" && o.default) return { clave: o.default, fuente: "default", invalido };
        const primera = Object.values(o).find((v) => typeof v === "string" && v !== "");
        if (typeof primera === "string") return { clave: primera, fuente: "primera", invalido };
      }
    } catch (_) {
      invalido = true;
    }
  }
  return legacy ? { clave: legacy, fuente: "legacy", invalido } : { clave: "", fuente: "ninguna", invalido };
}

// Claims YA VERIFICADOS (firma) de un token de usuario: exige sub, role = authenticated y
// exp vigente (ahora en segundos). Nunca se llama con claims sin verificar.
// deno-lint-ignore no-explicit-any
function claimsDeUsuarioValidos(c: any, ahora: number) {
  return !!c && typeof c.sub === "string" && c.sub !== "" && c.role === "authenticated" &&
    typeof c.exp === "number" && c.exp > ahora;
}

// S2 — Reautenticación: true si ALGÚN método de claims.amr ([{ method, timestamp }], tiempo en
// segundos) se usó hace como mucho ventanaSeg. Falla cerrada: sin amr, amr que no es arreglo,
// elementos sin timestamp numérico o ahoraSeg inválido -> false. "token_refresh" no cuenta:
// refrescar el token no es volver a autenticarse.
// deno-lint-ignore no-explicit-any
function autenticacionReciente(claims: any, ahoraSeg: number, ventanaSeg = 600) {
  if (!claims || typeof claims !== "object" || !Array.isArray(claims.amr)) return false;
  if (typeof ahoraSeg !== "number" || !Number.isFinite(ahoraSeg)) return false;
  if (typeof ventanaSeg !== "number" || !Number.isFinite(ventanaSeg) || ventanaSeg < 0) return false;
  const desde = ahoraSeg - ventanaSeg;
  return claims.amr.some((m) =>
    !!m && typeof m === "object" && m.method !== "token_refresh" &&
    typeof m.timestamp === "number" && Number.isFinite(m.timestamp) && m.timestamp >= desde);
}

// Payload de un JWT (sin verificar la firma: solo se usa con un token que auth.getUser ya
// aceptó). Cualquier forma inesperada -> null.
function payloadDeJwt(jwt: string) {
  try {
    const partes = String(jwt).split(".");
    if (partes.length !== 3) return null;
    const b64 = partes[1].replace(/-/g, "+").replace(/_/g, "/");
    const bin = atob(b64 + "=".repeat((4 - (b64.length % 4)) % 4));
    const o = JSON.parse(new TextDecoder().decode(Uint8Array.from(bin, (ch) => ch.charCodeAt(0))));
    return o && typeof o === "object" && !Array.isArray(o) ? o : null;
  } catch (_) {
    return null;
  }
}
// </puro>

// JWKS del proyecto que Supabase inyecta (SUPABASE_JWKS = {"keys": [...]}). Si no está o no
// es JSON, getClaims los descarga del endpoint JWKS del proyecto.
// deno-lint-ignore no-explicit-any
function jwksDelProyecto(): { keys: any[] } | undefined {
  try {
    const j = JSON.parse(Deno.env.get("SUPABASE_JWKS") ?? "");
    if (j && Array.isArray(j.keys) && j.keys.length) return { keys: j.keys };
  } catch (_) { /* sin JWKS inyectado */ }
  return undefined;
}

// deno-lint-ignore no-explicit-any
function esUsuarioInexistente(err: any): boolean {
  if (!err) return false;
  return err.code === "user_not_found" || err.status === 404 ||
    /user.*(not found|does not exist)/i.test(String(err.message || ""));
}

Deno.serve(async (req: Request) => {
  const origen = req.headers.get("Origin");

  if (req.method === "OPTIONS") {
    return new Response(null, { status: origenPermitido(origen) ? 204 : 403, headers: cabecerasCors(origen) });
  }
  if (req.method !== "POST") {
    return responder(origen, 405, { ok: false, error: "metodo_no_permitido" });
  }
  if (origen && !origenPermitido(origen)) {
    return responder(origen, 403, { ok: false, error: "origen_no_permitido" });
  }

  const url = Deno.env.get("SUPABASE_URL");
  const sel = elegirClaveSecreta(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");
  if (sel.invalido) console.error("[eliminar-cuenta] SUPABASE_SECRET_KEYS no es JSON válido; se intenta el respaldo legacy");
  if (!url || !sel.clave) {
    console.error("[eliminar-cuenta] faltan SUPABASE_URL o la clave secreta (SUPABASE_SECRET_KEYS / SUPABASE_SERVICE_ROLE_KEY)");
    return responder(origen, 500, { ok: false, error: "configuracion_incompleta" });
  }

  const auth = req.headers.get("Authorization") || "";
  const jwt = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  if (!jwt) return responder(origen, 401, { ok: false, error: "no_autenticado" });

  const admin = createClient(url, sel.clave, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });

  // 1) uid SOLO desde el JWT.
  let uid = "";
  let usuarioExiste = true;
  let claimsToken: unknown = null;   // claims del JWT para la reautenticación (S2)
  const { data: datosUsuario, error: errUsuario } = await admin.auth.getUser(jwt);
  if (!errUsuario && datosUsuario?.user?.id) {
    uid = datosUsuario.user.id;
    // auth.getUser ya aceptó este token; su payload da amr. Si el sub no calza, no se usa.
    const p = payloadDeJwt(jwt);
    claimsToken = p && p.sub === uid ? p : null;
  } else if (esUsuarioInexistente(errUsuario)) {
    // Reintento idempotente: el usuario ya no existe. Sin gateway que verifique, la firma se
    // verifica aquí (getClaims con el JWKS del proyecto) antes de confiar en el sub.
    let claims: unknown = null;
    try {
      const { data: dc, error: errClaims } = await admin.auth.getClaims(jwt, jwksDelProyecto());
      if (!errClaims && dc?.claims) claims = dc.claims;
    } catch (_) {
      claims = null;
    }
    if (!claimsDeUsuarioValidos(claims, Math.floor(Date.now() / 1000))) {
      return responder(origen, 401, { ok: false, error: "no_autenticado" });
    }
    uid = (claims as { sub: string }).sub;
    usuarioExiste = false;
    claimsToken = claims;
  } else {
    return responder(origen, 401, { ok: false, error: "no_autenticado" });
  }

  // 1b) S2: inicio de sesión reciente, ANTES de cualquier borrado (también en el reintento
  // idempotente, que puede borrar filas sueltas).
  if (!autenticacionReciente(claimsToken, Math.floor(Date.now() / 1000), VENTANA_REAUTH_SEG)) {
    console.info("[eliminar-cuenta] reautenticación requerida para " + uidCorto(uid));
    return responder(origen, 401, { ok: false, error: "reauth_required" });
  }

  // 2) Borrado real del usuario (CASCADE en las 9 tablas).
  if (usuarioExiste) {
    const { error: errBorrar } = await admin.auth.admin.deleteUser(uid, false);
    if (errBorrar && !esUsuarioInexistente(errBorrar)) {
      console.error("[eliminar-cuenta] deleteUser falló para " + uidCorto(uid) + ": " + (errBorrar.status || "") + " " + (errBorrar.code || ""));
      return responder(origen, 500, { ok: false, error: "error_borrando_usuario" });
    }
  }

  // 3) Verificación: 0 filas en las 9 tablas. Si quedara algo, borrado explícito y recuento.
  const verificacion: Record<string, number> = {};
  const borradasExplicitas: Record<string, number> = {};
  for (const tabla of TABLAS) {
    const { count, error } = await admin.from(tabla).select("user_id", { count: "exact", head: true }).eq("user_id", uid);
    if (error) {
      console.error("[eliminar-cuenta] no se pudo contar " + tabla + " para " + uidCorto(uid) + ": " + (error.code || ""));
      return responder(origen, 500, { ok: false, error: "error_verificando" });
    }
    let n = count || 0;
    if (n > 0) {
      const { error: errDel } = await admin.from(tabla).delete().eq("user_id", uid);
      if (errDel) {
        console.error("[eliminar-cuenta] no se pudo borrar " + tabla + " para " + uidCorto(uid) + ": " + (errDel.code || ""));
        return responder(origen, 500, { ok: false, error: "error_borrando_filas" });
      }
      borradasExplicitas[tabla] = n;
      const { count: resto, error: errResto } = await admin.from(tabla).select("user_id", { count: "exact", head: true }).eq("user_id", uid);
      if (errResto) return responder(origen, 500, { ok: false, error: "error_verificando" });
      n = resto || 0;
    }
    verificacion[tabla] = n;
  }

  const quedan = Object.values(verificacion).some((n) => n > 0);
  if (quedan) {
    console.error("[eliminar-cuenta] quedaron filas tras el borrado explícito para " + uidCorto(uid));
    return responder(origen, 500, { ok: false, error: "filas_remanentes", verificacion });
  }

  const hubo = Object.keys(borradasExplicitas).length > 0;
  console.info("[eliminar-cuenta] cuenta " + uidCorto(uid) + (usuarioExiste ? " eliminada" : " ya no existía") +
    (hubo ? "; borrado explícito en " + Object.keys(borradasExplicitas).join(",") : ""));
  return responder(origen, 200, hubo ? { ok: true, verificacion, borradasExplicitas } : { ok: true, verificacion });
});
