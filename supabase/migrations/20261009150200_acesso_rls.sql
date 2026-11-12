create or replace function privado.papel_atual()
returns public.papel
language sql stable security definer set search_path = ''
as $$
  select p.papel from public.perfis p where p.id = auth.uid() and p.ativo;
$$;

create or replace function privado.escola_atual()
returns smallint
language sql stable security definer set search_path = ''
as $$
  select p.escola_id from public.perfis p where p.id = auth.uid() and p.ativo;
$$;

create or replace function privado.carteira_atual()
returns text
language sql stable security definer set search_path = ''
as $$
  select p.carteira_id from public.perfis p where p.id = auth.uid() and p.ativo;
$$;

create or replace function privado.mfa_ok()
returns boolean
language sql stable set search_path = ''
as $$
  select coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2';
$$;

create or replace function privado.acesso_ok()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select case privado.papel_atual()
           when 'gerente'     then privado.mfa_ok()
           when 'coordenador' then privado.mfa_ok()
           when 'analista'    then privado.mfa_ok()
           when 'direcao'     then true
           when 'oficineiro'  then true
           else false
         end;
$$;

create or replace function privado.ve_tudo()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select privado.acesso_ok() and privado.papel_atual() in ('gerente', 'coordenador');
$$;

create or replace function privado.ve_escola(p_escola smallint)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select privado.acesso_ok() and case privado.papel_atual()
    when 'gerente'     then true
    when 'coordenador' then true
    when 'analista'    then exists (select 1 from public.escolas e where e.id = p_escola and e.carteira_id = privado.carteira_atual())
    when 'direcao'     then p_escola = privado.escola_atual()
    when 'oficineiro'  then p_escola = privado.escola_atual()
    else false
  end;
$$;

create or replace function privado.hoje()
returns date
language sql stable set search_path = ''
as $$
  select (now() at time zone 'America/Sao_Paulo')::date;
$$;

create or replace function privado.mes_editavel(p_oficineiro uuid, p_data date)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select p_data <= privado.hoje()
     and not exists (select 1 from public.relatorios_mensais r
                     where r.oficineiro_id = p_oficineiro
                       and r.competencia = date_trunc('month', p_data)::date
                       and r.status <> 'devolvido')
     and (date_trunc('month', p_data) = date_trunc('month', privado.hoje())
          or exists (select 1 from public.relatorios_mensais r
                     where r.oficineiro_id = p_oficineiro
                       and r.competencia = date_trunc('month', p_data)::date
                       and r.status = 'devolvido'));
$$;

revoke all on function privado.papel_atual(), privado.escola_atual(), privado.carteira_atual(), privado.mfa_ok(),
  privado.acesso_ok(), privado.ve_tudo(), privado.ve_escola(smallint), privado.hoje(), privado.mes_editavel(uuid, date)
  from public, anon;
grant execute on function privado.papel_atual(), privado.escola_atual(), privado.carteira_atual(), privado.mfa_ok(),
  privado.acesso_ok(), privado.ve_tudo(), privado.ve_escola(smallint), privado.hoje(), privado.mes_editavel(uuid, date)
  to authenticated;

revoke all on all tables in schema public from anon, authenticated;

grant select on public.carteiras, public.escolas, public.perfis, public.jornada_pessoas, public.presencas,
  public.aulas_registro, public.relatorios_mensais, public.visitas, public.onboarding_os to authenticated;

grant select (id, os_id, nome, email, cpf_mascara, matricula, cargo, tipo, lotacao_original, escola_id, carteira_id,
  status, baixa_data, baixa_forma, baixa_obs, baixa_por) on public.onboarding_itens to authenticated;

grant insert (oficineiro_id, escola_id, data, inicio, fim, turma, tipo, solucao, presentes, matriculados, situacao, motivo, conteudo)
  on public.aulas_registro to authenticated;
grant update (inicio, fim, turma, tipo, solucao, presentes, matriculados, situacao, motivo, conteudo)
  on public.aulas_registro to authenticated;

grant insert (analista_id, escola_id, data, tipo, subtipo, participantes, solucao, observacao) on public.visitas to authenticated;
grant update (data, tipo, subtipo, participantes, solucao, observacao) on public.visitas to authenticated;

create policy carteiras_ler on public.carteiras for select to authenticated
  using ((select privado.acesso_ok()));

create policy escolas_ler on public.escolas for select to authenticated
  using ((select privado.acesso_ok()));

create policy perfis_ler on public.perfis for select to authenticated
  using (
    id = (select auth.uid())
    or (select privado.ve_tudo())
    or (escola_id is not null and privado.ve_escola(escola_id))
  );

create policy jornada_ler on public.jornada_pessoas for select to authenticated
  using ((select privado.papel_atual()) in ('gerente', 'coordenador', 'analista') and privado.ve_escola(escola_id));

create policy presencas_ler on public.presencas for select to authenticated
  using (privado.ve_escola(escola_id) and ((select privado.papel_atual()) <> 'oficineiro' or oficineiro_id = (select auth.uid())));

create policy aulas_ler on public.aulas_registro for select to authenticated
  using (privado.ve_escola(escola_id) and ((select privado.papel_atual()) <> 'oficineiro' or oficineiro_id = (select auth.uid())));

create policy aulas_incluir on public.aulas_registro for insert to authenticated
  with check (
    (select privado.papel_atual()) = 'oficineiro'
    and oficineiro_id = (select auth.uid())
    and escola_id = (select privado.escola_atual())
    and privado.mes_editavel(oficineiro_id, data)
  );

create policy aulas_alterar on public.aulas_registro for update to authenticated
  using (
    (select privado.papel_atual()) = 'oficineiro'
    and oficineiro_id = (select auth.uid())
    and check_direcao is distinct from 'ok'
    and privado.mes_editavel(oficineiro_id, data)
  )
  with check (
    oficineiro_id = (select auth.uid())
    and escola_id = (select privado.escola_atual())
    and privado.mes_editavel(oficineiro_id, data)
  );

create policy relatorios_ler on public.relatorios_mensais for select to authenticated
  using (privado.ve_escola(escola_id) and ((select privado.papel_atual()) <> 'oficineiro' or oficineiro_id = (select auth.uid())));

create policy visitas_ler on public.visitas for select to authenticated
  using ((select privado.papel_atual()) <> 'oficineiro' and privado.ve_escola(escola_id));

create policy visitas_incluir on public.visitas for insert to authenticated
  with check ((select privado.papel_atual()) = 'analista' and analista_id = (select auth.uid()) and privado.ve_escola(escola_id));

create policy visitas_alterar on public.visitas for update to authenticated
  using ((select privado.papel_atual()) = 'analista' and analista_id = (select auth.uid()) and (select privado.acesso_ok()))
  with check (analista_id = (select auth.uid()) and privado.ve_escola(escola_id));

create policy os_ler on public.onboarding_os for select to authenticated
  using ((select privado.acesso_ok()) and (select privado.papel_atual()) in ('gerente', 'coordenador', 'analista'));

create policy onb_itens_ler on public.onboarding_itens for select to authenticated
  using (
    (select privado.ve_tudo())
    or ((select privado.papel_atual()) = 'analista' and (select privado.acesso_ok()) and carteira_id = (select privado.carteira_atual()))
  );
