/* ============================================================================================
   Telora · S1 · REVERSA de M2 y M1 — NO EJECUTAR sin aprobación explícita
   --------------------------------------------------------------------------------------------
   Orden obligatorio:
     PASO 0 (DML, a mano, por cuenta): devolver dispositivo_escritor a un device_id concreto en
            las cuentas activadas con 'multi:v2'. NO dejarlo en NULL: con NULL, el primer
            dispositivo con el candado confirmado que abra la app reclama el rol y, si no tiene
            base local, hace el resync (upsert de lo suyo + DELETE en la nube de lo que no tiene).
     PASO 1 (DML): borrar físicamente los tombstones. Si se quitara deleted_at con tombstones
            vivos, esas filas volverían a contar como existentes.
     PASO 2: M2 (funciones).
     PASO 3: M1 (triggers, índices, columnas, función, secuencia).
   REPLICA IDENTITY se queda en DEFAULT a propósito (no se revierte): con FULL, un DELETE emite
   la fila completa por Realtime sin pasar por RLS. Es una mejora de seguridad independiente de
   S1 y nada en el cliente depende de recibir la fila anterior completa (registrarEventoRealtime
   solo la registra). La línea que volvería a FULL queda comentada en el PASO 3.
   Respaldo antes de empezar: JSON de la app + CSV de las 9 tablas.
   ============================================================================================ */

-- ---- PASO 0 · revisar primero qué cuentas están en modo multi (solo lectura) ----
select user_id, dispositivo_escritor, modificado_por, updated_at
from public.config_compartida where dispositivo_escritor = 'multi:v2';
-- y elegir, por cuenta, el device_id que vuelve a ser el escritor único:
-- update public.config_compartida set dispositivo_escritor = '<DEVICE_ID>' where user_id = '<UID>';

begin;

-- ---- PASO 1 · tombstones (DML) ----
-- goal_aportes antes que goals (FK goal_aportes -> goals).
delete from public.goal_aportes        where deleted_at is not null;
delete from public.goals               where deleted_at is not null;
delete from public.expenses            where deleted_at is not null;
delete from public.incomes             where deleted_at is not null;
delete from public.debts               where deleted_at is not null;
delete from public.transfers           where deleted_at is not null;
delete from public.cuentas_financieras where deleted_at is not null;
delete from public.config_compartida   where deleted_at is not null;

-- ---- PASO 2 · M2 ----
drop function if exists public.sync_aplicar_lote(text, jsonb);
drop function if exists public.sync_aplicar_config(text, bigint, jsonb);
drop function if exists public.sync_cambios_desde(text, int);
drop function if exists public.sync_lectura_completa();
drop function if exists public.sync_activar_multi();

-- ---- PASO 3 · M1 ----
do $$
declare t text;
begin
  foreach t in array array['cuentas_financieras','transfers','expenses','incomes','debts',
                           'goals','goal_aportes','config_compartida'] loop
    execute format('drop trigger if exists zz_telora_sync_meta on public.%I', t);
    execute format('alter table public.%I drop column if exists rev, drop column if exists txid, '
                   'drop column if exists deleted_at, drop column if exists modificado_por', t);
  end loop;
  -- Los índices (user_id, txid) caen con la columna txid; el drop explícito es por claridad.
  foreach t in array array['cuentas_financieras','transfers','expenses','incomes','debts',
                           'goals','goal_aportes'] loop
    execute format('drop index if exists public.%I', t || '_user_txid_idx');
    -- NO se vuelve a FULL (ver cabecera): mejora de seguridad independiente de S1.
    -- execute format('alter table public.%I replica identity full', t);
  end loop;
end $$;

alter table public.config_dispositivo drop column if exists nombre_dispositivo;
drop function if exists public.telora_sync_meta();
drop sequence if exists public.telora_rev_seq;

commit;

-- Verificación (solo lectura): ninguna columna de S1; REPLICA IDENTITY sigue en DEFAULT en las 9 tablas.
select c.relname as tabla,
       case c.relreplident when 'd' then 'default' when 'f' then 'full' when 'n' then 'nothing' else 'index' end as replica_identity,
       (select string_agg(a.attname, ',') from pg_attribute a
        where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
          and a.attname in ('rev','txid','deleted_at','modificado_por','nombre_dispositivo')) as columnas_s1_restantes
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('cuentas_financieras','transfers','expenses','incomes','debts','goals',
                    'goal_aportes','config_compartida','config_dispositivo')
order by 1;
