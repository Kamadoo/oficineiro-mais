revoke select on public.perfis from authenticated;
grant select (id, nome, papel, escola_id, carteira_id, turno, ativo, criado_em) on public.perfis to authenticated;

drop policy if exists perfis_ler on public.perfis;
create policy perfis_ler on public.perfis for select to authenticated
  using (
    (id = (select auth.uid()) and (select privado.mfa_ok()))
    or (select privado.ve_tudo())
    or (escola_id is not null and privado.ve_escola(escola_id))
  );

drop policy if exists aulas_incluir on public.aulas_registro;
create policy aulas_incluir on public.aulas_registro for insert to authenticated
  with check (
    (select privado.acesso_ok())
    and (select privado.papel_atual()) = 'oficineiro'
    and oficineiro_id = (select auth.uid())
    and escola_id = (select privado.escola_atual())
    and privado.mes_editavel(oficineiro_id, data)
  );

drop policy if exists aulas_alterar on public.aulas_registro;
create policy aulas_alterar on public.aulas_registro for update to authenticated
  using (
    (select privado.acesso_ok())
    and (select privado.papel_atual()) = 'oficineiro'
    and oficineiro_id = (select auth.uid())
    and check_direcao is distinct from 'ok'
    and privado.mes_editavel(oficineiro_id, data)
  )
  with check (
    (select privado.acesso_ok())
    and oficineiro_id = (select auth.uid())
    and escola_id = (select privado.escola_atual())
    and privado.mes_editavel(oficineiro_id, data)
  );

create or replace function privado.meu_acesso()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'papel', p.papel,
    'nome', case when privado.mfa_ok() then p.nome end,
    'usuario', case when privado.mfa_ok() then p.usuario end,
    'escola_id', case when privado.mfa_ok() then p.escola_id end,
    'carteira_id', case when privado.mfa_ok() then p.carteira_id end,
    'precisa_mfa', not privado.mfa_ok(),
    'precisa_criar_usuario', p.usuario is null,
    'precisa_trocar_senha', p.trocar_senha,
    'acesso_ok', privado.acesso_ok()
  )
  from public.perfis p
  where p.id = auth.uid() and p.ativo;
$$;

drop trigger if exists auditoria_carga_upd on public.jornada_pessoas;
create trigger auditoria_carga_upd after update on public.jornada_pessoas
  referencing old table as antigas new table as novas for each statement execute function auditoria.trigger_carga();
