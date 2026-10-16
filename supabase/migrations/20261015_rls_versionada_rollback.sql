/* ============================================================================================
   Telora · Día 24 · Tanda B — REVERSA de 20261015_rls_versionada.sql
   --------------------------------------------------------------------------------------------
   Restaura EXACTAMENTE el estado exportado de pg_policies antes de la migración:
     roles {public}; select/update/delete USING (auth.uid() = user_id);
     insert WITH CHECK (auth.uid() = user_id); update SIN WITH CHECK.
   y quita el search_path de set_updated_at (proconfig sin search_path, como estaba; si el
   respaldo previo mostró otro proconfig, ajustar la última sentencia antes de correrla).
   Misma guarda que la migración: aborta si hay políticas que no sean las 36 conocidas.
   Una sola transacción, idempotente.
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

-- config_compartida
alter table public.config_compartida enable row level security;
drop policy if exists config_compartida_select_own on public.config_compartida;
drop policy if exists config_compartida_insert_own on public.config_compartida;
drop policy if exists config_compartida_update_own on public.config_compartida;
drop policy if exists config_compartida_delete_own on public.config_compartida;
create policy config_compartida_select_own on public.config_compartida for select to public using (auth.uid() = user_id);
create policy config_compartida_insert_own on public.config_compartida for insert to public with check (auth.uid() = user_id);
create policy config_compartida_update_own on public.config_compartida for update to public using (auth.uid() = user_id);
create policy config_compartida_delete_own on public.config_compartida for delete to public using (auth.uid() = user_id);

-- config_dispositivo
alter table public.config_dispositivo enable row level security;
drop policy if exists config_dispositivo_select_own on public.config_dispositivo;
drop policy if exists config_dispositivo_insert_own on public.config_dispositivo;
drop policy if exists config_dispositivo_update_own on public.config_dispositivo;
drop policy if exists config_dispositivo_delete_own on public.config_dispositivo;
create policy config_dispositivo_select_own on public.config_dispositivo for select to public using (auth.uid() = user_id);
create policy config_dispositivo_insert_own on public.config_dispositivo for insert to public with check (auth.uid() = user_id);
create policy config_dispositivo_update_own on public.config_dispositivo for update to public using (auth.uid() = user_id);
create policy config_dispositivo_delete_own on public.config_dispositivo for delete to public using (auth.uid() = user_id);

-- cuentas_financieras
alter table public.cuentas_financieras enable row level security;
drop policy if exists cuentas_financieras_select_own on public.cuentas_financieras;
drop policy if exists cuentas_financieras_insert_own on public.cuentas_financieras;
drop policy if exists cuentas_financieras_update_own on public.cuentas_financieras;
drop policy if exists cuentas_financieras_delete_own on public.cuentas_financieras;
create policy cuentas_financieras_select_own on public.cuentas_financieras for select to public using (auth.uid() = user_id);
create policy cuentas_financieras_insert_own on public.cuentas_financieras for insert to public with check (auth.uid() = user_id);
create policy cuentas_financieras_update_own on public.cuentas_financieras for update to public using (auth.uid() = user_id);
create policy cuentas_financieras_delete_own on public.cuentas_financieras for delete to public using (auth.uid() = user_id);

-- debts
alter table public.debts enable row level security;
drop policy if exists debts_select_own on public.debts;
drop policy if exists debts_insert_own on public.debts;
drop policy if exists debts_update_own on public.debts;
drop policy if exists debts_delete_own on public.debts;
create policy debts_select_own on public.debts for select to public using (auth.uid() = user_id);
create policy debts_insert_own on public.debts for insert to public with check (auth.uid() = user_id);
create policy debts_update_own on public.debts for update to public using (auth.uid() = user_id);
create policy debts_delete_own on public.debts for delete to public using (auth.uid() = user_id);

-- expenses
alter table public.expenses enable row level security;
drop policy if exists expenses_select_own on public.expenses;
drop policy if exists expenses_insert_own on public.expenses;
drop policy if exists expenses_update_own on public.expenses;
drop policy if exists expenses_delete_own on public.expenses;
create policy expenses_select_own on public.expenses for select to public using (auth.uid() = user_id);
create policy expenses_insert_own on public.expenses for insert to public with check (auth.uid() = user_id);
create policy expenses_update_own on public.expenses for update to public using (auth.uid() = user_id);
create policy expenses_delete_own on public.expenses for delete to public using (auth.uid() = user_id);

-- goal_aportes
alter table public.goal_aportes enable row level security;
drop policy if exists goal_aportes_select_own on public.goal_aportes;
drop policy if exists goal_aportes_insert_own on public.goal_aportes;
drop policy if exists goal_aportes_update_own on public.goal_aportes;
drop policy if exists goal_aportes_delete_own on public.goal_aportes;
create policy goal_aportes_select_own on public.goal_aportes for select to public using (auth.uid() = user_id);
create policy goal_aportes_insert_own on public.goal_aportes for insert to public with check (auth.uid() = user_id);
create policy goal_aportes_update_own on public.goal_aportes for update to public using (auth.uid() = user_id);
create policy goal_aportes_delete_own on public.goal_aportes for delete to public using (auth.uid() = user_id);

-- goals
alter table public.goals enable row level security;
drop policy if exists goals_select_own on public.goals;
drop policy if exists goals_insert_own on public.goals;
drop policy if exists goals_update_own on public.goals;
drop policy if exists goals_delete_own on public.goals;
create policy goals_select_own on public.goals for select to public using (auth.uid() = user_id);
create policy goals_insert_own on public.goals for insert to public with check (auth.uid() = user_id);
create policy goals_update_own on public.goals for update to public using (auth.uid() = user_id);
create policy goals_delete_own on public.goals for delete to public using (auth.uid() = user_id);

-- incomes
alter table public.incomes enable row level security;
drop policy if exists incomes_select_own on public.incomes;
drop policy if exists incomes_insert_own on public.incomes;
drop policy if exists incomes_update_own on public.incomes;
drop policy if exists incomes_delete_own on public.incomes;
create policy incomes_select_own on public.incomes for select to public using (auth.uid() = user_id);
create policy incomes_insert_own on public.incomes for insert to public with check (auth.uid() = user_id);
create policy incomes_update_own on public.incomes for update to public using (auth.uid() = user_id);
create policy incomes_delete_own on public.incomes for delete to public using (auth.uid() = user_id);

-- transfers
alter table public.transfers enable row level security;
drop policy if exists transfers_select_own on public.transfers;
drop policy if exists transfers_insert_own on public.transfers;
drop policy if exists transfers_update_own on public.transfers;
drop policy if exists transfers_delete_own on public.transfers;
create policy transfers_select_own on public.transfers for select to public using (auth.uid() = user_id);
create policy transfers_insert_own on public.transfers for insert to public with check (auth.uid() = user_id);
create policy transfers_update_own on public.transfers for update to public using (auth.uid() = user_id);
create policy transfers_delete_own on public.transfers for delete to public using (auth.uid() = user_id);

-- set_updated_at: vuelve a no tener search_path propio.
alter function public.set_updated_at() reset search_path;

commit;
