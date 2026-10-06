/* ============================================================================================
   Telora · S1 · Pruebas de M1 + M2 con ROLLBACK (nada queda guardado)
   --------------------------------------------------------------------------------------------
   Cómo correrlo (SQL Editor de Supabase):
     1. Reemplazar <UID_PRUEBA> (UNA sola vez, línea marcada) por el uid de la cuenta de prueba
        DESECHABLE. Nunca la de MARCADOR_CORREO_ELIMINADO (el script aborta si el correo empieza así).
     2. Ejecutar TODO el script de una vez.
     3. El resultado sale como un ERROR a propósito: «RESULTADOS T7 …» con una línea por caso.
        Ese error es lo que garantiza el rollback aunque el editor confirmara solo; la línea
        final «rollback;» cierra la transacción abortada. Copiar el texto completo del error.
   Notas:
     - Cada caso va en su propio bloque BEGIN/EXCEPTION: un error en un caso se informa como
       FALLA con su SQLSTATE y no oculta los demás (si un caso falla, los que dependen de él
       también pueden fallar).
     - telora_rev_seq NO retrocede con el rollback: quedan huecos en rev. Es inocuo.
     - Dentro de UNA transacción todas las escrituras comparten txid; por eso el caso i) prueba
       que el cursor excluye lo confirmado ANTES de esta transacción y que la propia
       transacción (en curso) queda en o sobre el cursor, es decir, se releería.
   ============================================================================================ */

begin;

select set_config('telora.uid_prueba', '<UID_PRUEBA>', true);   -- <<< ÚNICO lugar con el uid

-- Guardas (como postgres, antes de cambiar de rol).
do $$
declare v_email text;
begin
  if current_setting('telora.uid_prueba') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'Falta reemplazar <UID_PRUEBA> por un uuid';
  end if;
  select email into v_email from auth.users where id = current_setting('telora.uid_prueba')::uuid;
  if v_email is null then raise exception 'El uid de prueba no existe en auth.users'; end if;
  if v_email ilike 'MARCADOR_CORREO_ELIMINADO%' then raise exception 'ABORTADO: es la cuenta MARCADOR_CORREO_ELIMINADO'; end if;
  if not exists (select 1 from pg_proc where proname = 'sync_aplicar_lote') then
    raise exception 'M2 no está instalada';
  end if;
end $$;

select set_config('request.jwt.claims',
  json_build_object('sub', current_setting('telora.uid_prueba'), 'role', 'authenticated')::text, true);
set local role authenticated;

do $$
declare
  v_uid     uuid := auth.uid();
  v_dev     constant text := 'dev-prueba-A';
  v_claims  constant text := current_setting('request.jwt.claims', true);
  v_out     text := '';
  v_n       int := 0;
  v_okn     int := 0;
  v_ok      boolean;
  v_det     text;
  r         jsonb;
  r2        jsonb;
  v_rev1    bigint;
  v_rev2    bigint;
  v_rev3    bigint;
  v_reve2   bigint;
  v_fila    jsonb;
  v_ops     jsonb;
  v_cursor  text;
  v_t0      timestamptz;
  v_ms1     numeric;
  v_ms2     numeric;
  v_cnt     int;
  v_prev    int;
  v_crev    bigint;
  v_esc     text;
  v_txt     text;
begin
  if v_uid is null then raise exception 'auth.uid() es NULL: revisar request.jwt.claims'; end if;

  -- ---------------------------------------------------------------- a) insert nuevo
  begin
    r := public.sync_aplicar_lote(v_dev, jsonb_build_array(jsonb_build_object(
      'tabla','expenses','id','t7prueba-e1','tipo','upsert','base_rev',null,
      'fila', jsonb_build_object('date','2026-10-07','amount',15990,'category','Prueba',
                                 'method','Prueba','description','T7 a','nombre','Prueba a'))));
    v_rev1 := (r->0->>'rev')::bigint;
    select modificado_por into v_txt from public.expenses where user_id = v_uid and id = 't7prueba-e1';
    v_ok  := r->0->>'estado' = 'ok' and v_rev1 is not null and v_txt = v_dev;
    v_det := r::text || ' | modificado_por=' || coalesce(v_txt, 'NULL');
  exception when others then v_ok := false; v_det := 'ERROR ' || sqlstate || ' ' || sqlerrm; end;
  v_n := v_n + 1; if v_ok then v_okn := v_okn + 1; end if;
  v_out := v_out || format(E'a) %s · insert nuevo -> ok + rev · %s\n', case when v_ok then 'OK' else 'FALLA' end, left(v_det, 400));

  -- ---------------------------------------------------------------- b) update con base_rev correcto
  begin
    r := public.sync_aplicar_lote(v_dev, jsonb_build_array(jsonb_build_object(
      'tabla','expenses','id','t7prueba-e1','tipo','upsert','base_rev',v_rev1,
      'fila', jsonb_build_object('amount',16990,'description','T7 b'))));
    v_rev2 := (r->0->>'rev')::bigint;
    v_ok  := r->0->>'estado' = 'ok' and v_rev2 > v_rev1
             and (select amount::text from public.expenses where user_id = v_uid and id = 't7prueba-e1') = '16990';
    v_det := format('rev %s -> %s · %s', v_rev1, v_rev2, r::text);
  exception when others then v_ok := false; v_det := 'ERROR ' || sqlstate || ' ' || sqlerrm; end;
  v_n := v_n + 1; if v_ok then v_okn := v_okn + 1; end if;
  v_out := v_out || format(E'b) %s · update con base_rev correcto -> ok, rev aumenta · %s\n', case when v_ok then 'OK' else 'FALLA' end, left(v_det, 400));

  -- ---------------------------------------------------------------- c) base_rev viejo
  begin
    r := public.sync_aplicar_lote(v_dev, jsonb_build_array(jsonb_build_object(
      'tabla','expenses','id','t7prueba-e1','tipo','upsert','base_rev',v_rev1,
      'fila', jsonb_build_object('amount',99999))));
    v_ok  := r->0->>'estado' = 'choque' and r->0->>'motivo' = 'version'
             and (r->0->'servidor'->>'amount')::numeric = 16990
             and (select amount::text from public.expenses where user_id = v_uid and id = 't7prueba-e1') = '16990';
    v_det := format('estado=%s motivo=%s servidor.amount=%s servidor.rev=%s',
                    r->0->>'estado', r->0->>'motivo', r->0->'servidor'->>'amount', r->0->'servidor'->>'rev');
  exception when others then v_ok := false; v_det := 'ERROR ' || sqlstate || ' ' || sqlerrm; end;
  v_n := v_n + 1; if v_ok then v_okn := v_okn + 1; end if;
  v_out := v_out || format(E'c) %s · base_rev viejo -> choque version + fila del servidor · %s\n', case when v_ok then 'OK' else 'FALLA' end, left(v_det, 400));

  -- ---------------------------------------------------------------- d) delete -> tombstone
  begin
    r := public.sync_aplicar_lote(v_dev, jsonb_build_array(jsonb_build_object(
      'tabla','expenses','id','t7prueba-e1','tipo','delete','base_rev',v_rev2,
      'fila', jsonb_build_object('id','t7prueba-e1'))));
    v_rev3 := (r->0->>'rev')::bigint;
    select count(*) into v_cnt from public.expenses
      where user_id = v_uid and id = 't7prueba-e1' and deleted_at is not null;
    v_ok  := r->0->>'estado' = 'ok' and v_rev3 > v_rev2 and v_cnt = 1;
    v_det := format('rev %s -> %s · filas con tombstone=%s (1 = no hubo DELETE físico)', v_rev2, v_rev3, v_cnt);
  exception when others then v_ok := false; v_det := 'ERROR ' || sqlstate || ' ' || sqlerrm; end;
  v_n := v_n + 1; if v_ok then v_okn := v_okn + 1; end if;
  v_out := v_out || format(E'd) %s · delete -> tombstone, sin DELETE físico · %s\n', case when v_ok then 'OK' else 'FALLA' end, left(v_det, 400));

  -- ---------------------------------------------------------------- e) upsert sobre tombstone
  begin
    r := public.sync_aplicar_lote(v_dev, jsonb_build_array(jsonb_build_object(
      'tabla','expenses','id','t7prueba-e1','tipo','upsert','base_rev',v_rev2,
      'fila', jsonb_build_object('amount',17990))));
    select count(*) into v_cnt from public.expenses
      where user_id = v_uid and id = 't7prueba-e1' and deleted_at is not null;
    v_ok  := r->0->>'estado' = 'choque' and r->0->>'motivo' = 'eliminado' and v_cnt = 1;
    v_det := format('estado=%s motivo=%s sigue_con_tombstone=%s', r->0->>'estado', r->0->>'motivo', v_cnt = 1);
  exception when others then v_ok := false; v_det := 'ERROR ' || sqlstate || ' ' || sqlerrm; end;
  v_n := v_n + 1; if v_ok then v_okn := v_okn + 1; end if;
  v_out := v_out || format(E'e) %s · upsert sobre tombstone (base_rev previo al borrado) -> choque eliminado · %s\n', case when v_ok then 'OK' else 'FALLA' end, left(v_det, 400));

  -- ---------------------------------------------------------------- f) reintento idéntico -> ya_aplicado
  -- numeric: el reintento manda amount como TEXTO ("12345") y la primera vez como número;
  -- date: "2026-10-07"; jsonb/array: fechas_confirmadas. Controles negativos: arreglo más
  -- corto (no basta la contención) y otro device con el mismo contenido.
  begin
    v_fila := jsonb_build_object('date','2026-10-07','amount',12345,'category','Prueba','method','Prueba',
                                 'description','T7 f','nombre','Prueba f',
                                 'fechas_confirmadas', jsonb_build_array('2026-10-01','2026-10-02'));
    r := public.sync_aplicar_lote(v_dev, jsonb_build_array(jsonb_build_object(
      'tabla','expenses','id','t7prueba-e2','tipo','upsert','base_rev',null,'fila',v_fila)));
    v_reve2 := (r->0->>'rev')::bigint;
    -- reintento: misma op (base_rev null), amount como texto
    r2 := public.sync_aplicar_lote(v_dev, jsonb_build_array(
      jsonb_build_object('tabla','expenses','id','t7prueba-e2','tipo','upsert','base_rev',null,
                         'fila', v_fila || jsonb_build_object('amount','12345')),
      jsonb_build_object('tabla','expenses','id','t7prueba-e2','tipo','upsert','base_rev',null,
                         'fila', v_fila || jsonb_build_object('fechas_confirmadas', jsonb_build_array('2026-10-01'))),
      jsonb_build_object('tabla','expenses','id','t7prueba-e2','tipo','upsert','base_rev',null,
                         'fila', v_fila)));
    v_ok := r->0->>'estado' = 'ok'
            and r2->0->>'estado' = 'ok' and (r2->0->>'ya_aplicado')::boolean and (r2->0->>'rev')::bigint = v_reve2
            and r2->1->>'estado' = 'choque'
            and r2->2->>'estado' = 'ok';   -- idéntico otra vez: ya_aplicado
    -- otro device, mismo contenido -> choque
    r := public.sync_aplicar_lote('dev-prueba-B', jsonb_build_array(jsonb_build_object(
      'tabla','expenses','id','t7prueba-e2','tipo','upsert','base_rev',null,'fila',v_fila)));
    v_ok := v_ok and r->0->>'estado' = 'choque';
    v_det := format('reintento=%s ya_aplicado=%s · arreglo_corto=%s · idéntico=%s · otro_device=%s',
                    r2->0->>'estado', r2->0->>'ya_aplicado', r2->1->>'estado', r2->2->>'estado', r->0->>'estado');
  exception when others then v_ok := false; v_det := 'ERROR ' || sqlstate || ' ' || sqlerrm; end;
  v_n := v_n + 1; if v_ok then v_okn := v_okn + 1; end if;
  v_out := v_out || format(E'f) %s · reintento idéntico -> ok ya_aplicado (numeric/date/jsonb) · %s\n', case when v_ok then 'OK' else 'FALLA' end, left(v_det, 400));

  -- ---------------------------------------------------------------- g) aporte sobre meta eliminada
  begin
    r := public.sync_aplicar_lote(v_dev, jsonb_build_array(jsonb_build_object(
      'tabla','goals','id','t7prueba-g1','tipo','upsert','base_rev',null,
      'fila', jsonb_build_object('name','Meta prueba T7','indefinida',true,'fecha_creacion','2026-10-07'))));
    r := public.sync_aplicar_lote(v_dev, jsonb_build_array(jsonb_build_object(
      'tabla','goals','id','t7prueba-g1','tipo','delete','base_rev',(r->0->>'rev')::bigint,
      'fila', jsonb_build_object('id','t7prueba-g1'))));
    r2 := public.sync_aplicar_lote(v_dev, jsonb_build_array(
      jsonb_build_object('tabla','goal_aportes','id','t7prueba-a1','tipo','upsert','base_rev',null,
        'fila', jsonb_build_object('goal_id','t7prueba-g1','monto',5000,'fecha','2026-10-07')),
      jsonb_build_object('tabla','goal_aportes','id','t7prueba-a2','tipo','upsert','base_rev',null,
        'fila', jsonb_build_object('goal_id','t7prueba-no-existe','monto',5000,'fecha','2026-10-07'))));
    select count(*) into v_cnt from public.goal_aportes where user_id = v_uid and id in ('t7prueba-a1','t7prueba-a2');
    v_ok  := r->0->>'estado' = 'ok' and r2->0->>'motivo' = 'padre_eliminado'
             and r2->1->>'motivo' = 'padre_inexistente' and v_cnt = 0;
    v_det := format('meta borrada=%s · aporte=%s/%s · aporte sin meta=%s/%s · aportes escritos=%s',
                    r->0->>'estado', r2->0->>'estado', r2->0->>'motivo', r2->1->>'estado', r2->1->>'motivo', v_cnt);
  exception when others then v_ok := false; v_det := 'ERROR ' || sqlstate || ' ' || sqlerrm; end;
  v_n := v_n + 1; if v_ok then v_okn := v_okn + 1; end if;
  v_out := v_out || format(E'g) %s · aporte sobre meta eliminada -> padre_eliminado · %s\n', case when v_ok then 'OK' else 'FALLA' end, left(v_det, 400));

  -- ---------------------------------------------------------------- h) op inválida, el lote sigue
  begin
    r := public.sync_aplicar_lote(v_dev, jsonb_build_array(
      jsonb_build_object('tabla','expenses','id','t7prueba-h1','tipo','upsert','base_rev',null,
                         'fila', jsonb_build_object('columna_que_no_existe',1)),
      jsonb_build_object('tabla','tabla_que_no_existe','id','t7prueba-h2','tipo','upsert','base_rev',null,
                         'fila', jsonb_build_object('amount',1)),
      jsonb_build_object('tabla','expenses','id','t7prueba-h3','tipo','upsert','base_rev',null,
                         'fila', jsonb_build_object('date','2026-10-07','amount',100,'category','Prueba',
                                                    'method','Prueba','description','T7 h','nombre','Prueba h'))));
    v_ok  := r->0->>'estado' = 'invalida' and r->0->>'motivo' = 'sin_columnas'
             and r->1->>'estado' = 'invalida' and r->1->>'motivo' = 'tabla'
             and r->2->>'estado' = 'ok';
    v_det := format('[%s/%s, %s/%s, %s]', r->0->>'estado', r->0->>'motivo', r->1->>'estado', r->1->>'motivo', r->2->>'estado');
  exception when others then v_ok := false; v_det := 'ERROR ' || sqlstate || ' ' || sqlerrm; end;
  v_n := v_n + 1; if v_ok then v_okn := v_okn + 1; end if;
  v_out := v_out || format(E'h) %s · op sin columnas válidas -> invalida y el lote sigue · %s\n', case when v_ok then 'OK' else 'FALLA' end, left(v_det, 400));

  -- ---------------------------------------------------------------- i) lectura completa -> cursor -> cambios_desde
  begin
    select count(*) into v_prev from public.expenses where user_id = v_uid and id not like 't7prueba-%';
    r := public.sync_lectura_completa();
    v_cursor := r->>'cursor';
    r2 := public.sync_aplicar_lote(v_dev, jsonb_build_array(jsonb_build_object(
      'tabla','expenses','id','t7prueba-i1','tipo','upsert','base_rev',null,
      'fila', jsonb_build_object('date','2026-10-07','amount',1,'category','Prueba','method','Prueba',
                                 'description','T7 i','nombre','Prueba i'))));
    r2 := public.sync_cambios_desde(v_cursor, 1000);
    select count(*) into v_cnt from jsonb_array_elements(r2->'filas'->'expenses') e
      where e->>'id' not like 't7prueba-%';
    v_ok := v_cursor is not null
            and v_cursor::xid8 <= pg_current_xact_id()                                   -- esta transacción se releería
            and exists (select 1 from jsonb_array_elements(r->'filas'->'expenses') e
                        where e->>'id' = 't7prueba-e1' and e->>'deleted_at' is not null)   -- D1: trae tombstones
            and exists (select 1 from jsonb_array_elements(r2->'filas'->'expenses') e where e->>'id' = 't7prueba-i1')
            and v_cnt = 0                                                               -- nada confirmado antes
            and (public.sync_cambios_desde(v_cursor, 1)->>'truncado')::boolean;         -- truncado con límite 1
    v_det := format('cursor=%s · filas previas de la cuenta=%s (en cambios_desde: %s)%s · truncado(límite 1)=%s',
                    v_cursor, v_prev, v_cnt,
                    case when v_prev = 0 then ' [sin filas previas: la exclusión no se observa]' else '' end,
                    public.sync_cambios_desde(v_cursor, 1)->>'truncado');
  exception when others then v_ok := false; v_det := 'ERROR ' || sqlstate || ' ' || sqlerrm; end;
  v_n := v_n + 1; if v_ok then v_okn := v_okn + 1; end if;
  v_out := v_out || format(E'i) %s · lectura completa -> cursor; cambios_desde trae lo nuevo · %s\n', case when v_ok then 'OK' else 'FALLA' end, left(v_det, 400));

  -- ---------------------------------------------------------------- j) otro uid (RLS)
  begin
    perform set_config('request.jwt.claims',
      json_build_object('sub', gen_random_uuid()::text, 'role', 'authenticated')::text, true);
    r := public.sync_lectura_completa();
    r2 := public.sync_aplicar_lote('dev-intruso', jsonb_build_array(jsonb_build_object(
      'tabla','expenses','id','t7prueba-e2','tipo','upsert','base_rev',v_reve2,
      'fila', jsonb_build_object('amount',1))));
    update public.expenses set amount = 1 where id = 't7prueba-e2';
    get diagnostics v_cnt = row_count;
    delete from public.expenses where id like 't7prueba-%';
    get diagnostics v_prev = row_count;
    perform set_config('request.jwt.claims', v_claims, true);
    v_ok := jsonb_array_length(r->'filas'->'expenses') = 0
            and r2->0->>'estado' = 'choque' and r2->0->>'motivo' = 'no_existe'
            and v_cnt = 0 and v_prev = 0
            and (select amount::text from public.expenses where user_id = v_uid and id = 't7prueba-e2') = '12345';
    v_det := format('ve=%s filas · RPC=%s/%s · update directo=%s · delete directo=%s · e2 intacto=%s',
                    jsonb_array_length(r->'filas'->'expenses'), r2->0->>'estado', r2->0->>'motivo', v_cnt, v_prev,
                    (select amount::text from public.expenses where user_id = v_uid and id = 't7prueba-e2'));
  exception when others then
    perform set_config('request.jwt.claims', v_claims, true);
    v_ok := false; v_det := 'ERROR ' || sqlstate || ' ' || sqlerrm;
  end;
  v_n := v_n + 1; if v_ok then v_okn := v_okn + 1; end if;
  v_out := v_out || format(E'j) %s · otro uid no ve ni modifica nada · %s\n', case when v_ok then 'OK' else 'FALLA' end, left(v_det, 400));

  -- ---------------------------------------------------------------- k) lote de 200 ops (tiempo)
  begin
    select jsonb_agg(jsonb_build_object('tabla','expenses','id', format('t7prueba-k%s', lpad(g::text, 3, '0')),
             'tipo','upsert','base_rev',null,
             'fila', jsonb_build_object('date','2026-10-07','amount',g,'category','Prueba','method','Prueba',
                                        'description','T7 k','nombre','Prueba k')))
      into v_ops from generate_series(1, 200) g;
    v_t0 := clock_timestamp();
    r := public.sync_aplicar_lote(v_dev, v_ops);
    v_ms1 := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
    -- 200 updates con su base_rev (el camino más caro: bloqueo + update)
    select jsonb_agg(jsonb_build_object('tabla','expenses','id', e->>'clave','tipo','upsert',
             'base_rev',(e->>'rev')::bigint,'fila', jsonb_build_object('amount', 1000)))
      into v_ops from jsonb_array_elements(r) e;
    v_t0 := clock_timestamp();
    r2 := public.sync_aplicar_lote(v_dev, v_ops);
    v_ms2 := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
    select count(*) into v_cnt from jsonb_array_elements(r) e where e->>'estado' = 'ok';
    select count(*) into v_prev from jsonb_array_elements(r2) e where e->>'estado' = 'ok';
    v_ok  := v_cnt = 200 and v_prev = 200 and v_ms1 < 2000 and v_ms2 < 2000;
    v_det := format('200 inserts: %s ok en %s ms · 200 updates: %s ok en %s ms (objetivo < 2000 ms)', v_cnt, v_ms1, v_prev, v_ms2);
  exception when others then v_ok := false; v_det := 'ERROR ' || sqlstate || ' ' || sqlerrm; end;
  v_n := v_n + 1; if v_ok then v_okn := v_okn + 1; end if;
  v_out := v_out || format(E'k) %s · tiempo de un lote de 200 ops · %s\n', case when v_ok then 'OK' else 'FALLA' end, left(v_det, 400));

  -- ---------------------------------------------------------------- l) config_compartida (D5)
  begin
    select rev, dispositivo_escritor into v_crev, v_esc from public.config_compartida where user_id = v_uid;
    r := public.sync_aplicar_config(v_dev, v_crev, jsonb_build_object('categorias', jsonb_build_array('Prueba T7 l')));
    r2 := public.sync_aplicar_config(v_dev, v_crev, jsonb_build_object('categorias', jsonb_build_array('Otra T7 l')));
    v_ok := r->>'estado' = 'ok' and (v_crev is null or (r->>'rev')::bigint > v_crev)
            and r2->>'estado' = 'choque' and r2->>'motivo' = 'version'
            and (select dispositivo_escritor is not distinct from v_esc from public.config_compartida where user_id = v_uid);
    v_det := format('fila previa=%s · CAS correcto=%s · CAS viejo=%s/%s · dispositivo_escritor intacto',
                    case when v_crev is null then 'no (insert)' else 'sí' end, r->>'estado', r2->>'estado', r2->>'motivo');
  exception when others then v_ok := false; v_det := 'ERROR ' || sqlstate || ' ' || sqlerrm; end;
  v_n := v_n + 1; if v_ok then v_okn := v_okn + 1; end if;
  v_out := v_out || format(E'l) %s · sync_aplicar_config: compare-and-set y choque · %s\n', case when v_ok then 'OK' else 'FALLA' end, left(v_det, 400));

  -- ---------------------------------------------------------------- m) activación por cuenta
  begin
    r := public.sync_activar_multi();
    v_ok := (r->>'ok')::boolean and r->>'escritor' = 'multi:v2'
            and (select dispositivo_escritor from public.config_compartida where user_id = v_uid) = 'multi:v2';
    v_det := r::text;
  exception when others then v_ok := false; v_det := 'ERROR ' || sqlstate || ' ' || sqlerrm; end;
  v_n := v_n + 1; if v_ok then v_okn := v_okn + 1; end if;
  v_out := v_out || format(E'm) %s · sync_activar_multi -> multi:v2 · %s\n', case when v_ok then 'OK' else 'FALLA' end, left(v_det, 400));

  -- ---------------------------------------------------------------- n) escritura directa (cliente viejo)
  -- En la vida real cada petición es su propia transacción; acá hay que limpiar la marca que
  -- dejaron los RPC anteriores dentro de esta misma transacción.
  begin
    perform set_config('telora.via_rpc', '', true);
    select rev into v_rev1 from public.expenses where user_id = v_uid and id = 't7prueba-e2';
    update public.expenses set description = 'directo' where user_id = v_uid and id = 't7prueba-e2';
    select rev, modificado_por into v_rev2, v_txt from public.expenses where user_id = v_uid and id = 't7prueba-e2';
    v_ok  := v_rev2 > v_rev1 and v_txt is null;
    v_det := format('rev %s -> %s · modificado_por=%s', v_rev1, v_rev2, coalesce(v_txt, 'NULL'));
  exception when others then v_ok := false; v_det := 'ERROR ' || sqlstate || ' ' || sqlerrm; end;
  v_n := v_n + 1; if v_ok then v_okn := v_okn + 1; end if;
  v_out := v_out || format(E'n) %s · escritura directa: el trigger sube rev y deja modificado_por NULL · %s\n', case when v_ok then 'OK' else 'FALLA' end, left(v_det, 400));

  raise exception using message = format(E'RESULTADOS T7 (todo se revierte) · %s/%s OK\n%s', v_okn, v_n, v_out);
end $$;

rollback;
