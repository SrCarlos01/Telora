/* Edge Function «eliminar-cuenta» (Telora · T2b)
   ------------------------------------------------------------------------------------------
   REQUISITOS DE DESPLIEGUE (no omitir):
     1. Desplegar con «Verify JWT» ACTIVADO. El gateway de Supabase verifica la firma del JWT
        antes de llegar acá; esta función igual valida el usuario con auth.getUser y, solo si el
        usuario ya no existe (reintento tras un borrado exitoso), se apoya en esa verificación
        para leer el uid del token ya verificado.
     2. Usa SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY, que Supabase inyecta por defecto en toda
        Edge Function. No se crea ningún secret a mano y la service role NUNCA va al cliente
        ni al repositorio.

   Qué hace (solo POST; el uid sale SOLO del JWT, jamás del cuerpo de la petición):
     1. Obtiene el usuario con el JWT del header Authorization. Sin JWT válido -> 401.
     2. auth.admin.deleteUser(uid, false): borrado real (no soft delete). Las 9 tablas tienen
        FK user_id -> auth.users(id) ON DELETE CASCADE, así que sus filas se van con el usuario
        y, desde ese instante, ningún insert con ese user_id puede volver a entrar (23503).
     3. Verifica con la service role que las 9 tablas quedaron en 0 filas para ese uid. Si alguna
        tuviera filas, las borra explícitamente (goal_aportes antes que goals) y lo informa.
   Idempotente: si el usuario ya no existe en auth, solo verifica 0 filas y responde ok.
   Respuesta: { ok, verificacion: { tabla: 0, ... }, borradasExplicitas?: { tabla: n } }.
   Logs sin datos personales: solo el uid truncado. */

import { createClient } from "npm:@supabase/supabase-js@2";

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

// Payload del JWT (ya verificado por el gateway con «Verify JWT»). Solo se usa cuando
// auth.getUser responde que el usuario no existe: el caso idempotente de un reintento.
function claimsDelToken(jwt: string): Record<string, unknown> | null {
  try {
    const parte = jwt.split(".")[1];
    const b64 = parte.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(parte.length / 4) * 4, "=");
    return JSON.parse(atob(b64));
  } catch (_) {
    return null;
  }
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
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceRole) {
    console.error("[eliminar-cuenta] faltan SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY");
    return responder(origen, 500, { ok: false, error: "configuracion_incompleta" });
  }

  const auth = req.headers.get("Authorization") || "";
  const jwt = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  if (!jwt) return responder(origen, 401, { ok: false, error: "no_autenticado" });

  const admin = createClient(url, serviceRole, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });

  // 1) uid SOLO desde el JWT.
  let uid = "";
  let usuarioExiste = true;
  const { data: datosUsuario, error: errUsuario } = await admin.auth.getUser(jwt);
  if (!errUsuario && datosUsuario?.user?.id) {
    uid = datosUsuario.user.id;
  } else if (esUsuarioInexistente(errUsuario)) {
    // Token con firma válida (Verify JWT) de un usuario que ya no existe: reintento idempotente.
    const c = claimsDelToken(jwt);
    const ahora = Math.floor(Date.now() / 1000);
    if (!c || typeof c.sub !== "string" || c.role !== "authenticated" || typeof c.exp !== "number" || c.exp <= ahora) {
      return responder(origen, 401, { ok: false, error: "no_autenticado" });
    }
    uid = c.sub;
    usuarioExiste = false;
  } else {
    return responder(origen, 401, { ok: false, error: "no_autenticado" });
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
