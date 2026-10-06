/* ============================================================================================
   Telora · S1 · M2 — RPC de sincronización con varios escritores (requiere M1)
   --------------------------------------------------------------------------------------------
   Cinco funciones, todas SECURITY INVOKER (RLS sigue aplicando: auth.uid() = user_id) y con
   search_path fijo. Idempotente (create or replace).

   sync_aplicar_lote(p_device, p_ops)   -> jsonb[]   compare-and-set de las 7 tablas de datos
   sync_aplicar_config(p_device, p_base_rev, p_fila) -> jsonb   ídem para config_compartida (D5)
   sync_cambios_desde(p_cursor, p_limite) -> jsonb   puesta al día incremental (cursor xid8)
   sync_lectura_completa()               -> jsonb   todas las filas (con tombstones) + cursor (D1)
   sync_activar_multi()                  -> jsonb   dispositivo_escritor = 'multi:v2'

   Formato de una op de p_ops:
     { "tabla": "expenses", "id": "<id>", "tipo": "upsert"|"delete",
       "base_rev": <rev conocido> | null (fila nueva), "fila": { columna: valor, ... } }
   Resultado por op (mismo orden, con "i" = posición en p_ops):
     { i, tabla, clave, estado: "ok", rev, ya_aplicado? }
     { i, tabla, clave, estado: "choque", motivo, servidor }   motivo: version | eliminado |
                                                               no_existe | padre_eliminado |
                                                               padre_inexistente
     { i, tabla, clave, estado: "invalida", motivo }           (D3: el lote sigue)

   Reglas del compare-and-set (por op, con la fila bloqueada FOR UPDATE):
     - fila inexistente: delete -> ok (idempotente); upsert sin base_rev -> INSERT;
       upsert con base_rev -> choque 'no_existe' (borrada físicamente).
     - rev actual = base_rev: upsert -> UPDATE (y deleted_at = NULL: así se restaura un
       tombstone a propósito); delete -> deleted_at = now() (tombstone, nunca DELETE físico).
     - rev distinto: delete sobre un tombstone -> ok ya_aplicado; upsert cuyo contenido ya está
       (mismo device en modificado_por, columnas enviadas iguales tras normalizar por tipo de
       columna) -> ok ya_aplicado (reintento tras perder la respuesta); si no -> choque
       'eliminado' (hay tombstone) o 'version', con la fila del servidor.
     - aporte (goal_aportes) que se escribe sobre una meta con tombstone -> 'padre_eliminado';
       sobre una meta inexistente -> 'padre_inexistente' (en vez de abortar el lote por la FK).
   Sin bloques EXCEPTION a propósito: cada uno abre una subtransacción y 200 de ellas desbordan
   la caché de subxids. Un valor que no calza con el tipo de columna aborta la llamada (400);
   el cliente ya reparte el lote de a una op y aísla la culpable en «fallidas».
   La lista blanca de columnas se arma UNA vez por tabla y por llamada desde pg_attribute (D8).
   ============================================================================================ */

create or replace function public.sync_aplicar_lote(p_device text, p_ops jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_uid     uuid := auth.uid();
  c_tablas  constant text[] := array['cuentas_financieras','transfers','expenses','incomes',
                                     'debts','goals','goal_aportes'];
  c_meta    constant text[] := array['id','user_id','rev','txid','deleted_at','modificado_por',
                                     'updated_at','created_at'];
  v_permitidas jsonb := '{}';
  v_res     jsonb := '[]';
  v_i       int := -1;
  v_op      jsonb;
  v_tabla   text;
  v_id      text;
  v_tipo    text;
  v_base    bigint;
  v_fila    jsonb;
  v_cols    text[];
  v_lista   text;
  v_set     text;
  v_cur     jsonb;
  v_norm    jsonb;
  v_igual   boolean;
  v_rev     bigint;
  v_goal    text;
  v_padre   jsonb;
  v_motivo  text;
begin
  if v_uid is null then
    raise exception 'sync_aplicar_lote: sin sesión' using errcode = '42501';
  end if;
  if coalesce(p_device, '') = '' then
    raise exception 'sync_aplicar_lote: falta p_device' using errcode = '22023';
  end if;
  if jsonb_typeof(p_ops) is distinct from 'array' then
    raise exception 'sync_aplicar_lote: p_ops debe ser un arreglo' using errcode = '22023';
  end if;
  perform set_config('telora.via_rpc', '1', true);

  for v_op in select value from jsonb_array_elements(p_ops) loop
    v_i     := v_i + 1;
    v_tabla := v_op->>'tabla';
    v_id    := v_op->>'id';
    v_tipo  := v_op->>'tipo';
    v_fila  := case when jsonb_typeof(v_op->'fila') = 'object' then v_op->'fila' else '{}'::jsonb end;

    -- Validación (D3): la op inválida se informa y el lote sigue.
    v_motivo := case
      when v_tabla is null or not (v_tabla = any(c_tablas)) then 'tabla'
      when coalesce(v_id, '') = '' then 'id'
      when v_tipo is null or v_tipo not in ('upsert','delete') then 'tipo'
      when v_op ? 'base_rev' and jsonb_typeof(v_op->'base_rev') <> 'null'
           and (v_op->>'base_rev') !~ '^[0-9]{1,18}$' then 'base_rev'
    end;
    if v_motivo is not null then
      v_res := v_res || jsonb_build_object('i', v_i, 'tabla', v_tabla, 'clave', v_id,
                                           'estado', 'invalida', 'motivo', v_motivo);
      continue;
    end if;
    v_base := case when jsonb_typeof(v_op->'base_rev') = 'number' or jsonb_typeof(v_op->'base_rev') = 'string'
                   then (v_op->>'base_rev')::bigint end;

    -- Lista blanca de la tabla: una sola vez por llamada (D8).
    if not (v_permitidas ? v_tabla) then
      v_permitidas := v_permitidas || jsonb_build_object(v_tabla, (
        select coalesce(jsonb_agg(a.attname::text order by a.attnum), '[]'::jsonb)
        from pg_attribute a
        where a.attrelid = format('public.%I', v_tabla)::regclass
          and a.attnum > 0 and not a.attisdropped and a.attgenerated = ''
          and not (a.attname::text = any(c_meta))));
    end if;

    select coalesce(array_agg(k order by k), '{}'::text[]) into v_cols
    from jsonb_object_keys(v_fila) k
    where (v_permitidas->v_tabla) ? k;

    if v_tipo = 'upsert' and cardinality(v_cols) = 0 then
      v_res := v_res || jsonb_build_object('i', v_i, 'tabla', v_tabla, 'clave', v_id,
                                           'estado', 'invalida', 'motivo', 'sin_columnas');
      continue;
    end if;

    execute format('select to_jsonb(t) from public.%I t where t.user_id = $1 and t.id = $2 for update', v_tabla)
      into v_cur using v_uid, v_id;

    -- ¿Se puede escribir? (solo upsert de un aporte: la meta debe existir y estar viva)
    v_padre := null;
    if v_tipo = 'upsert' and v_tabla = 'goal_aportes' then
      v_goal := coalesce(v_fila->>'goal_id', v_cur->>'goal_id');
      select jsonb_build_object('deleted_at', g.deleted_at) into v_padre
      from public.goals g where g.user_id = v_uid and g.id = v_goal;
    end if;

    if v_cur is null then
      -- ---- La fila no existe ----
      if v_tipo = 'delete' then
        v_res := v_res || jsonb_build_object('i', v_i, 'tabla', v_tabla, 'clave', v_id,
                                             'estado', 'ok', 'rev', null, 'ya_aplicado', true);
      elsif v_base is not null then
        v_res := v_res || jsonb_build_object('i', v_i, 'tabla', v_tabla, 'clave', v_id,
                                             'estado', 'choque', 'motivo', 'no_existe', 'servidor', null);
      elsif v_tabla = 'goal_aportes' and (v_padre is null or v_padre->>'deleted_at' is not null) then
        v_res := v_res || jsonb_build_object('i', v_i, 'tabla', v_tabla, 'clave', v_id, 'estado', 'choque',
                                             'motivo', case when v_padre is null then 'padre_inexistente' else 'padre_eliminado' end,
                                             'servidor', null);
      else
        select string_agg(format('%I', k), ', ' order by k) into v_lista from unnest(v_cols) k;
        execute format('insert into public.%I (id, user_id, modificado_por, %s) '
                       'select $1, $2, $3, %s from jsonb_populate_record(null::public.%I, $4) returning rev',
                       v_tabla, v_lista, v_lista, v_tabla)
          into v_rev using v_id, v_uid, p_device, v_fila;
        v_res := v_res || jsonb_build_object('i', v_i, 'tabla', v_tabla, 'clave', v_id,
                                             'estado', 'ok', 'rev', v_rev);
      end if;

    elsif (v_cur->>'rev')::bigint = v_base then
      -- ---- Versión esperada: se aplica ----
      if v_tipo = 'delete' then
        if v_cur->>'deleted_at' is not null then
          v_res := v_res || jsonb_build_object('i', v_i, 'tabla', v_tabla, 'clave', v_id,
                                               'estado', 'ok', 'rev', (v_cur->>'rev')::bigint, 'ya_aplicado', true);
        else
          execute format('update public.%I set deleted_at = now(), modificado_por = $3 '
                         'where user_id = $1 and id = $2 returning rev', v_tabla)
            into v_rev using v_uid, v_id, p_device;
          v_res := v_res || jsonb_build_object('i', v_i, 'tabla', v_tabla, 'clave', v_id,
                                               'estado', 'ok', 'rev', v_rev);
        end if;
      elsif v_tabla = 'goal_aportes' and (v_padre is null or v_padre->>'deleted_at' is not null) then
        v_res := v_res || jsonb_build_object('i', v_i, 'tabla', v_tabla, 'clave', v_id, 'estado', 'choque',
                                             'motivo', case when v_padre is null then 'padre_inexistente' else 'padre_eliminado' end,
                                             'servidor', v_cur);
      else
        select string_agg(format('%I = r.%I', k, k), ', ' order by k) into v_set from unnest(v_cols) k;
        execute format('update public.%I t set %s, deleted_at = null, modificado_por = $3 '
                       'from jsonb_populate_record(null::public.%I, $4) r '
                       'where t.user_id = $1 and t.id = $2 returning t.rev',
                       v_tabla, v_set, v_tabla)
          into v_rev using v_uid, v_id, p_device, v_fila;
        v_res := v_res || jsonb_build_object('i', v_i, 'tabla', v_tabla, 'clave', v_id,
                                             'estado', 'ok', 'rev', v_rev);
      end if;

    else
      -- ---- Versión distinta (o base_rev null con fila existente) ----
      v_igual := false;
      if v_tipo = 'upsert' and v_cur->>'deleted_at' is null and v_cur->>'modificado_por' = p_device then
        -- Normaliza lo enviado con los tipos de la tabla (numeric, date, jsonb…) y compara
        -- columna a columna con IGUALDAD (no contención: un arreglo más corto NO calza).
        execute format('select to_jsonb(r) from jsonb_populate_record(null::public.%I, $1) r', v_tabla)
          into v_norm using v_fila;
        select bool_and((v_norm->k) is not distinct from (v_cur->k)) into v_igual from unnest(v_cols) k;
      end if;
      if (v_tipo = 'delete' and v_cur->>'deleted_at' is not null) or coalesce(v_igual, false) then
        v_res := v_res || jsonb_build_object('i', v_i, 'tabla', v_tabla, 'clave', v_id,
                                             'estado', 'ok', 'rev', (v_cur->>'rev')::bigint, 'ya_aplicado', true);
      else
        v_res := v_res || jsonb_build_object('i', v_i, 'tabla', v_tabla, 'clave', v_id, 'estado', 'choque',
                                             'motivo', case when v_cur->>'deleted_at' is not null then 'eliminado' else 'version' end,
                                             'servidor', v_cur);
      end if;
    end if;
  end loop;

  return v_res;
end $$;


/* config_compartida (una fila por usuario, sin id). Mismo compare-and-set; nunca toca
   dispositivo_escritor. En T7 solo detecta el choque (la fusión por campo es de T11). */
create or replace function public.sync_aplicar_config(p_device text, p_base_rev bigint, p_fila jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_uid    uuid := auth.uid();
  c_meta   constant text[] := array['user_id','rev','txid','deleted_at','modificado_por',
                                    'updated_at','created_at','dispositivo_escritor'];
  v_perm   text[];
  v_cols   text[];
  v_lista  text;
  v_set    text;
  v_cur    jsonb;
  v_norm   jsonb;
  v_igual  boolean;
  v_rev    bigint;
begin
  if v_uid is null then
    raise exception 'sync_aplicar_config: sin sesión' using errcode = '42501';
  end if;
  if coalesce(p_device, '') = '' then
    raise exception 'sync_aplicar_config: falta p_device' using errcode = '22023';
  end if;
  if jsonb_typeof(p_fila) is distinct from 'object' then
    return jsonb_build_object('tabla', 'config_compartida', 'estado', 'invalida', 'motivo', 'fila');
  end if;
  perform set_config('telora.via_rpc', '1', true);

  select coalesce(array_agg(a.attname::text), '{}'::text[]) into v_perm
  from pg_attribute a
  where a.attrelid = 'public.config_compartida'::regclass
    and a.attnum > 0 and not a.attisdropped and a.attgenerated = ''
    and not (a.attname::text = any(c_meta));
  select coalesce(array_agg(k order by k), '{}'::text[]) into v_cols
  from jsonb_object_keys(p_fila) k where k = any(v_perm);
  if cardinality(v_cols) = 0 then
    return jsonb_build_object('tabla', 'config_compartida', 'estado', 'invalida', 'motivo', 'sin_columnas');
  end if;

  select to_jsonb(c) into v_cur from public.config_compartida c where c.user_id = v_uid for update;

  if v_cur is null then
    if p_base_rev is not null then
      return jsonb_build_object('tabla', 'config_compartida', 'estado', 'choque', 'motivo', 'no_existe', 'servidor', null);
    end if;
    select string_agg(format('%I', k), ', ' order by k) into v_lista from unnest(v_cols) k;
    execute format('insert into public.config_compartida (user_id, modificado_por, %s) '
                   'select $1, $2, %s from jsonb_populate_record(null::public.config_compartida, $3) returning rev',
                   v_lista, v_lista)
      into v_rev using v_uid, p_device, p_fila;
    return jsonb_build_object('tabla', 'config_compartida', 'estado', 'ok', 'rev', v_rev);
  end if;

  if (v_cur->>'rev')::bigint = p_base_rev then
    select string_agg(format('%I = r.%I', k, k), ', ' order by k) into v_set from unnest(v_cols) k;
    execute format('update public.config_compartida c set %s, modificado_por = $2 '
                   'from jsonb_populate_record(null::public.config_compartida, $3) r '
                   'where c.user_id = $1 returning c.rev', v_set)
      into v_rev using v_uid, p_device, p_fila;
    return jsonb_build_object('tabla', 'config_compartida', 'estado', 'ok', 'rev', v_rev);
  end if;

  v_igual := false;
  if v_cur->>'modificado_por' = p_device then
    select to_jsonb(r) into v_norm from jsonb_populate_record(null::public.config_compartida, p_fila) r;
    select bool_and((v_norm->k) is not distinct from (v_cur->k)) into v_igual from unnest(v_cols) k;
  end if;
  if coalesce(v_igual, false) then
    return jsonb_build_object('tabla', 'config_compartida', 'estado', 'ok',
                              'rev', (v_cur->>'rev')::bigint, 'ya_aplicado', true);
  end if;
  return jsonb_build_object('tabla', 'config_compartida', 'estado', 'choque', 'motivo', 'version', 'servidor', v_cur);
end $$;


/* Puesta al día: filas (con tombstones) de las 8 tablas escritas por transacciones con
   txid >= p_cursor. El cursor nuevo es el xmin del snapshot ACTUAL, tomado antes de leer:
   toda transacción con xid menor ya había terminado, así que lo suyo está en esta lectura;
   las que siguen en curso (una que confirma tarde) tienen xid >= cursor y vuelven a salir en
   la próxima llamada. Releer es inocuo: el cliente ignora rev <= conocido.
   Si alguna tabla supera p_limite: { truncado: true } SIN filas; el cliente hace
   sync_lectura_completa() y adopta su cursor (D1). */
create or replace function public.sync_cambios_desde(p_cursor text, p_limite int default 1000)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_uid    uuid := auth.uid();
  v_hasta  xid8 := pg_snapshot_xmin(pg_current_snapshot());
  v_desde  xid8;
  v_lim    int := least(greatest(coalesce(p_limite, 1000), 1), 5000);
  v_out    jsonb := '{}';
  v_f      jsonb;
  t        text;
begin
  if v_uid is null then
    raise exception 'sync_cambios_desde: sin sesión' using errcode = '42501';
  end if;
  if coalesce(p_cursor, '') !~ '^[0-9]{1,20}$' then
    raise exception 'sync_cambios_desde: cursor inválido' using errcode = '22023';
  end if;
  v_desde := p_cursor::xid8;
  foreach t in array array['cuentas_financieras','transfers','expenses','incomes','debts',
                           'goals','goal_aportes','config_compartida'] loop
    execute format('select coalesce(jsonb_agg(to_jsonb(x) order by x.txid, x.rev), ''[]''::jsonb) '
                   'from (select * from public.%I where user_id = $1 and txid >= $2 order by txid, rev limit $3) x', t)
      into v_f using v_uid, v_desde, v_lim + 1;
    if jsonb_array_length(v_f) > v_lim then
      return jsonb_build_object('truncado', true, 'tabla', t);
    end if;
    v_out := v_out || jsonb_build_object(t, v_f);
  end loop;
  return jsonb_build_object('truncado', false, 'cursor', v_hasta::text, 'filas', v_out,
                            'servidor_ahora', now());
end $$;


/* Lectura completa (D1): las 8 tablas con tombstones + el cursor, en la MISMA llamada (un
   solo snapshot: la función es STABLE). */
create or replace function public.sync_lectura_completa()
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_uid    uuid := auth.uid();
  v_hasta  xid8 := pg_snapshot_xmin(pg_current_snapshot());
  v_out    jsonb := '{}';
  v_f      jsonb;
  t        text;
begin
  if v_uid is null then
    raise exception 'sync_lectura_completa: sin sesión' using errcode = '42501';
  end if;
  foreach t in array array['cuentas_financieras','transfers','expenses','incomes','debts',
                           'goals','goal_aportes','config_compartida'] loop
    execute format('select coalesce(jsonb_agg(to_jsonb(x) order by x.rev), ''[]''::jsonb) '
                   'from public.%I x where x.user_id = $1', t)
      into v_f using v_uid;
    v_out := v_out || jsonb_build_object(t, v_f);
  end loop;
  return jsonb_build_object('cursor', v_hasta::text, 'filas', v_out, 'servidor_ahora', now());
end $$;


/* Activación por cuenta: dispositivo_escritor = 'multi:v2'. Los clientes viejos (escritor
   único) ven que el escritor ya no son ellos y dejan de escribir (Realtime o al cargar). No
   marca telora.via_rpc a propósito: modificado_por queda NULL (cambio administrativo). */
create or replace function public.sync_activar_multi()
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_uid  uuid := auth.uid();
  v_ant  text;
begin
  if v_uid is null then
    raise exception 'sync_activar_multi: sin sesión' using errcode = '42501';
  end if;
  select c.dispositivo_escritor into v_ant from public.config_compartida c where c.user_id = v_uid for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'sin_config');
  end if;
  update public.config_compartida set dispositivo_escritor = 'multi:v2' where user_id = v_uid;
  return jsonb_build_object('ok', true, 'escritor_anterior', v_ant, 'escritor', 'multi:v2');
end $$;


revoke all on function public.sync_aplicar_lote(text, jsonb)           from public, anon;
revoke all on function public.sync_aplicar_config(text, bigint, jsonb) from public, anon;
revoke all on function public.sync_cambios_desde(text, int)            from public, anon;
revoke all on function public.sync_lectura_completa()                  from public, anon;
revoke all on function public.sync_activar_multi()                     from public, anon;
grant execute on function public.sync_aplicar_lote(text, jsonb)           to authenticated;
grant execute on function public.sync_aplicar_config(text, bigint, jsonb) to authenticated;
grant execute on function public.sync_cambios_desde(text, int)            to authenticated;
grant execute on function public.sync_lectura_completa()                  to authenticated;
grant execute on function public.sync_activar_multi()                     to authenticated;

-- Verificación (solo lectura): 5 funciones, todas SECURITY INVOKER, ejecutables por
-- authenticated y NO por anon.
select p.proname,
       pg_get_function_identity_arguments(p.oid) as args,
       p.prosecdef as security_definer,
       has_function_privilege('authenticated', p.oid, 'execute') as authenticated_ejecuta,
       has_function_privilege('anon', p.oid, 'execute') as anon_ejecuta
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname like 'sync\_%'
order by 1;
