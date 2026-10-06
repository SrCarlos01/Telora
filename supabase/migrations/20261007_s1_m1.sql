do $$ begin if current_setting('server_version_num')::int < 130000
  then raise exception 'Postgres < 13: xid8 no disponible'; end if; end $$;

/* ============================================================================================
   Telora · S1 · M1 — Versión por fila, tombstones y origen (migración ADITIVA e IDEMPOTENTE)
   --------------------------------------------------------------------------------------------
   Qué agrega (en las 7 tablas de datos y en config_compartida):
     rev            bigint  NOT NULL  versión de la fila: nextval de telora_rev_seq en CADA
                                      insert/update (trigger zz_telora_sync_meta). Es la versión
                                      que usa el compare-and-set de los RPC de M2.
     txid           xid8    NOT NULL  transacción que escribió la fila (pg_current_xact_id()).
                                      El cursor de puesta al día es pg_snapshot_xmin(...): toda
                                      transacción con xid menor ya estaba confirmada al leer.
     deleted_at     timestamptz       tombstone (borrado lógico). NULL = viva.
     modificado_por text              device_id que escribió por RPC; NULL si fue una escritura
                                      directa (cliente sin el protocolo nuevo, Table Editor).
   Además:
     config_dispositivo.nombre_dispositivo text  (D6: «Chrome en Windows», lo llena el cliente).
     REPLICA IDENTITY DEFAULT en las 9 tablas (D7). Con FULL, un DELETE emitía la fila completa
     por Realtime sin pasar por RLS. registrarEventoRealtime() lee payload.old, pero solo para el
     registro en consola y el buffer (ninguna decisión depende de él); con DEFAULT recibe la PK.
     Índice (user_id, txid) en las 7 tablas de datos para la puesta al día.

   Compatibilidad con clientes viejos (BUILD bd2cea5): sus upserts no mandan estas columnas, así
   que ON CONFLICT no las toca salvo lo que pone el trigger (rev/txid nuevos, modificado_por
   NULL). Sus DELETE siguen siendo físicos (el bloqueo de escritura directa es M3, Tanda T15).

   Idempotente (D4): la función del trigger se crea ANTES del bloque do; columnas con
   ADD COLUMN IF NOT EXISTS; DROP TRIGGER IF EXISTS antes de cada CREATE TRIGGER; índices con
   IF NOT EXISTS. Correrlo dos veces deja el mismo esquema.

   Las filas existentes reciben rev distinto por fila (default volátil: reescribe la tabla sin
   disparar triggers, así que updated_at NO cambia) y txid = el de esta migración. Después se
   quita el default: desde ahí rev/txid los pone SOLO el trigger (NOT NULL se verifica después
   de los BEFORE triggers).
   Reversa: 20261007_s1_reversa.sql.
   ============================================================================================ */

begin;

create sequence if not exists public.telora_rev_seq as bigint;
-- El trigger corre con el rol de quien escribe (authenticated): necesita nextval.
grant usage on sequence public.telora_rev_seq to authenticated;

create or replace function public.telora_sync_meta() returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.rev  := nextval('public.telora_rev_seq');
  new.txid := pg_current_xact_id();
  -- Solo los RPC de sync (M2) marcan telora.via_rpc = '1' (set_config local a su transacción).
  -- Cualquier otra escritura deja el origen como desconocido.
  if coalesce(current_setting('telora.via_rpc', true), '') <> '1' then
    new.modificado_por := null;
  end if;
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['cuentas_financieras','transfers','expenses','incomes','debts',
                           'goals','goal_aportes','config_compartida'] loop
    execute format('alter table public.%I add column if not exists rev bigint not null default nextval(''public.telora_rev_seq'')', t);
    execute format('alter table public.%I add column if not exists txid xid8 not null default pg_current_xact_id()', t);
    execute format('alter table public.%I add column if not exists deleted_at timestamptz', t);
    execute format('alter table public.%I add column if not exists modificado_por text', t);
    execute format('alter table public.%I alter column rev drop default', t);
    execute format('alter table public.%I alter column txid drop default', t);
    execute format('drop trigger if exists zz_telora_sync_meta on public.%I', t);
    execute format('create trigger zz_telora_sync_meta before insert or update on public.%I '
                   'for each row execute function public.telora_sync_meta()', t);
  end loop;

  foreach t in array array['cuentas_financieras','transfers','expenses','incomes','debts',
                           'goals','goal_aportes'] loop
    execute format('create index if not exists %I on public.%I (user_id, txid)', t || '_user_txid_idx', t);
    execute format('alter table public.%I replica identity default', t);
  end loop;
end $$;

alter table public.config_compartida  replica identity default;
alter table public.config_dispositivo replica identity default;
alter table public.config_dispositivo add column if not exists nombre_dispositivo text;

commit;

-- Verificación (solo lectura): debe listar 8 triggers zz_telora_sync_meta, 7 índices
-- *_user_txid_idx y las 9 tablas con replica_identity = 'default'.
select c.relname as tabla,
       exists (select 1 from pg_trigger t where t.tgrelid = c.oid and t.tgname = 'zz_telora_sync_meta') as trigger_meta,
       exists (select 1 from pg_class i join pg_index x on x.indexrelid = i.oid
               where x.indrelid = c.oid and i.relname = c.relname || '_user_txid_idx') as indice_txid,
       case c.relreplident when 'd' then 'default' when 'f' then 'full' when 'n' then 'nothing' else 'index' end as replica_identity
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('cuentas_financieras','transfers','expenses','incomes','debts','goals',
                    'goal_aportes','config_compartida','config_dispositivo')
order by 1;
