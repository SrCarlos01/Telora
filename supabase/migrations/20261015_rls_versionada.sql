/* ============================================================================================
   Telora · Día 24 · Tanda B — RLS versionada + search_path de set_updated_at
   --------------------------------------------------------------------------------------------
   Hasta ahora las 36 políticas de producción (9 tablas × select/insert/update/delete) no
   estaban en el repo. Esta migración las versiona con la MISMA lógica y tres cambios:
     1. TO authenticated en vez de {public}. anon nunca tuvo acceso real (auth.uid() es NULL y
        NULL = user_id no es verdadero); ahora ni siquiera se evalúa la política para anon.
     2. (select auth.uid()) en vez de auth.uid(): Postgres lo evalúa una vez por consulta
        (initPlan) y no una vez por fila. Mismo valor. Resuelve auth_rls_initplan (36 avisos).
     3. update con WITH CHECK explícito. Sin WITH CHECK, Postgres ya usaba el USING para la
        fila nueva; escribirlo no cambia el comportamiento, solo lo deja a la vista.
   Además: set_updated_at con search_path = '' (aviso function_search_path_mutable). Con ''
   sigue resolviendo pg_catalog (now(), current_timestamp…) de forma implícita; la guarda de
   abajo aborta si el cuerpo hace algo más que asignar updated_at.

   Mismos nombres de política. Sin SECURITY DEFINER. Una sola transacción: si una guarda o
   sentencia falla, no queda nada aplicado. Idempotente: correrla dos veces deja lo mismo.
   La Edge Function eliminar-cuenta usa la clave secreta (bypassa RLS): no la afecta.
   Reversa: 20261015_rls_versionada_rollback.sql.
   ============================================================================================ */

begin;

-- Guarda: las 9 tablas existen y cada una tiene EXACTAMENTE sus 4 políticas *_own, permisivas,
-- en el estado exportado (roles {public}, auth.uid() directo, update sin WITH CHECK) o en el de
-- 20261015_rls_versionada.sql (roles {authenticated}, (select auth.uid()), update con WITH CHECK).
-- Cualquier otra cosa (política extra, faltante, restrictiva, con otra lógica) aborta TODO: no
-- se reemplaza lo que no se conoce, y crear una política faltante abriría acceso.
do $$
declare
  q_viejo constant text := '(auth.uid()=user_id)';
  q_nuevo constant text := '((SELECTauth.uid()ASuid)=user_id)';
  v_t     text;
  v_ok    int;
  v_total int;
begin
  foreach v_t in array array['config_compartida','config_dispositivo','cuentas_financieras','debts',
                             'expenses','goal_aportes','goals','incomes','transfers'] loop
    if to_regclass('public.' || v_t) is null then
      raise exception 'ABORTADO: no existe la tabla public.%', v_t;
    end if;
    select count(*) into v_total from pg_policies where schemaname = 'public' and tablename = v_t;
    select count(*) into v_ok
      from pg_policies p
      cross join lateral (select regexp_replace(coalesce(p.qual, ''), '\s', '', 'g')       as q,
                                 regexp_replace(coalesce(p.with_check, ''), '\s', '', 'g') as w) x
     where p.schemaname = 'public' and p.tablename = v_t and p.permissive = 'PERMISSIVE'
       and (   (p.roles = '{public}'::name[] and (
                   (p.policyname = v_t || '_select_own' and p.cmd = 'SELECT' and x.q = q_viejo and x.w = '')
                or (p.policyname = v_t || '_insert_own' and p.cmd = 'INSERT' and x.q = ''      and x.w = q_viejo)
                or (p.policyname = v_t || '_update_own' and p.cmd = 'UPDATE' and x.q = q_viejo and x.w = '')
                or (p.policyname = v_t || '_delete_own' and p.cmd = 'DELETE' and x.q = q_viejo and x.w = '')))
            or (p.roles = '{authenticated}'::name[] and (
                   (p.policyname = v_t || '_select_own' and p.cmd = 'SELECT' and x.q = q_nuevo and x.w = '')
                or (p.policyname = v_t || '_insert_own' and p.cmd = 'INSERT' and x.q = ''      and x.w = q_nuevo)
                or (p.policyname = v_t || '_update_own' and p.cmd = 'UPDATE' and x.q = q_nuevo and x.w = q_nuevo)
                or (p.policyname = v_t || '_delete_own' and p.cmd = 'DELETE' and x.q = q_nuevo and x.w = ''))));
    if v_ok <> 4 or v_total <> 4 then
      raise exception 'ABORTADO: public.% no calza con lo esperado (% políticas, % reconocidas). Revisar pg_policies antes de seguir.',
        v_t, v_total, v_ok;
    end if;
  end loop;
end $$;

-- Guarda de set_updated_at: existe, no es SECURITY DEFINER, es plpgsql y su cuerpo (sin
-- espacios, en minúsculas) es exactamente «begin new.updated_at = <hora actual>; return new;
-- end;». Si no calza, abortar y revisar a mano con pg_get_functiondef.
do $$
declare v_src text;
begin
  select regexp_replace(lower(p.prosrc), '\s', '', 'g') into v_src
    from pg_proc p join pg_language l on l.oid = p.prolang
   where p.oid = to_regprocedure('public.set_updated_at()')
     and not p.prosecdef and l.lanname = 'plpgsql';
  if v_src is null then
    raise exception 'ABORTADO: public.set_updated_at() no existe, es SECURITY DEFINER o no es plpgsql';
  end if;
  if v_src !~ ('^beginnew\.updated_at:?=(pg_catalog\.)?'
               '(now\(\)|current_timestamp|clock_timestamp\(\)|statement_timestamp\(\)|transaction_timestamp\(\)'
               '|timezone\(''utc''(::text)?,(pg_catalog\.)?now\(\)\)|now\(\)attimezone''utc''(::text)?)'
               ';returnnew;end;?$') then
    raise exception 'ABORTADO: set_updated_at() hace algo más que asignar updated_at: %', v_src;
  end if;
end $$;

-- config_compartida
alter table public.config_compartida enable row level security;
drop policy if exists config_compartida_select_own on public.config_compartida;
drop policy if exists config_compartida_insert_own on public.config_compartida;
drop policy if exists config_compartida_update_own on public.config_compartida;
drop policy if exists config_compartida_delete_own on public.config_compartida;
create policy config_compartida_select_own on public.config_compartida for select to authenticated using ((select auth.uid()) = user_id);
create policy config_compartida_insert_own on public.config_compartida for insert to authenticated with check ((select auth.uid()) = user_id);
create policy config_compartida_update_own on public.config_compartida for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy config_compartida_delete_own on public.config_compartida for delete to authenticated using ((select auth.uid()) = user_id);

-- config_dispositivo
alter table public.config_dispositivo enable row level security;
drop policy if exists config_dispositivo_select_own on public.config_dispositivo;
drop policy if exists config_dispositivo_insert_own on public.config_dispositivo;
drop policy if exists config_dispositivo_update_own on public.config_dispositivo;
drop policy if exists config_dispositivo_delete_own on public.config_dispositivo;
create policy config_dispositivo_select_own on public.config_dispositivo for select to authenticated using ((select auth.uid()) = user_id);
create policy config_dispositivo_insert_own on public.config_dispositivo for insert to authenticated with check ((select auth.uid()) = user_id);
create policy config_dispositivo_update_own on public.config_dispositivo for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy config_dispositivo_delete_own on public.config_dispositivo for delete to authenticated using ((select auth.uid()) = user_id);

-- cuentas_financieras
alter table public.cuentas_financieras enable row level security;
drop policy if exists cuentas_financieras_select_own on public.cuentas_financieras;
drop policy if exists cuentas_financieras_insert_own on public.cuentas_financieras;
drop policy if exists cuentas_financieras_update_own on public.cuentas_financieras;
drop policy if exists cuentas_financieras_delete_own on public.cuentas_financieras;
create policy cuentas_financieras_select_own on public.cuentas_financieras for select to authenticated using ((select auth.uid()) = user_id);
create policy cuentas_financieras_insert_own on public.cuentas_financieras for insert to authenticated with check ((select auth.uid()) = user_id);
create policy cuentas_financieras_update_own on public.cuentas_financieras for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy cuentas_financieras_delete_own on public.cuentas_financieras for delete to authenticated using ((select auth.uid()) = user_id);

-- debts
alter table public.debts enable row level security;
drop policy if exists debts_select_own on public.debts;
drop policy if exists debts_insert_own on public.debts;
drop policy if exists debts_update_own on public.debts;
drop policy if exists debts_delete_own on public.debts;
create policy debts_select_own on public.debts for select to authenticated using ((select auth.uid()) = user_id);
create policy debts_insert_own on public.debts for insert to authenticated with check ((select auth.uid()) = user_id);
create policy debts_update_own on public.debts for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy debts_delete_own on public.debts for delete to authenticated using ((select auth.uid()) = user_id);

-- expenses
alter table public.expenses enable row level security;
drop policy if exists expenses_select_own on public.expenses;
drop policy if exists expenses_insert_own on public.expenses;
drop policy if exists expenses_update_own on public.expenses;
drop policy if exists expenses_delete_own on public.expenses;
create policy expenses_select_own on public.expenses for select to authenticated using ((select auth.uid()) = user_id);
create policy expenses_insert_own on public.expenses for insert to authenticated with check ((select auth.uid()) = user_id);
create policy expenses_update_own on public.expenses for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy expenses_delete_own on public.expenses for delete to authenticated using ((select auth.uid()) = user_id);

-- goal_aportes
alter table public.goal_aportes enable row level security;
drop policy if exists goal_aportes_select_own on public.goal_aportes;
drop policy if exists goal_aportes_insert_own on public.goal_aportes;
drop policy if exists goal_aportes_update_own on public.goal_aportes;
drop policy if exists goal_aportes_delete_own on public.goal_aportes;
create policy goal_aportes_select_own on public.goal_aportes for select to authenticated using ((select auth.uid()) = user_id);
create policy goal_aportes_insert_own on public.goal_aportes for insert to authenticated with check ((select auth.uid()) = user_id);
create policy goal_aportes_update_own on public.goal_aportes for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy goal_aportes_delete_own on public.goal_aportes for delete to authenticated using ((select auth.uid()) = user_id);

-- goals
alter table public.goals enable row level security;
drop policy if exists goals_select_own on public.goals;
drop policy if exists goals_insert_own on public.goals;
drop policy if exists goals_update_own on public.goals;
drop policy if exists goals_delete_own on public.goals;
create policy goals_select_own on public.goals for select to authenticated using ((select auth.uid()) = user_id);
create policy goals_insert_own on public.goals for insert to authenticated with check ((select auth.uid()) = user_id);
create policy goals_update_own on public.goals for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy goals_delete_own on public.goals for delete to authenticated using ((select auth.uid()) = user_id);

-- incomes
alter table public.incomes enable row level security;
drop policy if exists incomes_select_own on public.incomes;
drop policy if exists incomes_insert_own on public.incomes;
drop policy if exists incomes_update_own on public.incomes;
drop policy if exists incomes_delete_own on public.incomes;
create policy incomes_select_own on public.incomes for select to authenticated using ((select auth.uid()) = user_id);
create policy incomes_insert_own on public.incomes for insert to authenticated with check ((select auth.uid()) = user_id);
create policy incomes_update_own on public.incomes for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy incomes_delete_own on public.incomes for delete to authenticated using ((select auth.uid()) = user_id);

-- transfers
alter table public.transfers enable row level security;
drop policy if exists transfers_select_own on public.transfers;
drop policy if exists transfers_insert_own on public.transfers;
drop policy if exists transfers_update_own on public.transfers;
drop policy if exists transfers_delete_own on public.transfers;
create policy transfers_select_own on public.transfers for select to authenticated using ((select auth.uid()) = user_id);
create policy transfers_insert_own on public.transfers for insert to authenticated with check ((select auth.uid()) = user_id);
create policy transfers_update_own on public.transfers for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy transfers_delete_own on public.transfers for delete to authenticated using ((select auth.uid()) = user_id);

-- set_updated_at: search_path vacío (solo pg_catalog, implícito).
alter function public.set_updated_at() set search_path = '';

commit;
