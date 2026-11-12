alter table public.aulas_registro drop constraint if exists aulas_registro_check_direcao_check;
alter table public.aulas_registro add constraint aulas_registro_check_direcao_check
  check (check_direcao in ('ok', 'contestada', 'corrigida'));

alter table public.relatorios_mensais
  add column if not exists devolvido_por uuid references public.perfis (id),
  add column if not exists devolvido_em  timestamptz,
  add column if not exists devolvido_papel text check (devolvido_papel in ('direcao', 'coordenador'));

drop policy if exists aulas_alterar on public.aulas_registro;
create policy aulas_alterar on public.aulas_registro for update to authenticated
  using (
    (select privado.acesso_ok())
    and (select privado.papel_atual()) = 'oficineiro'
    and oficineiro_id = (select auth.uid())
    and check_direcao is distinct from 'ok'
    and revisao_status is distinct from 'anulado'
    and (privado.mes_editavel(oficineiro_id, data)
         or revisao_status in ('devolvido', 'corrigido')
         or check_direcao in ('contestada', 'corrigida'))
  )
  with check (
    (select privado.acesso_ok())
    and oficineiro_id = (select auth.uid())
    and escola_id = (select privado.escola_atual())
    and revisao_status is distinct from 'anulado'
    and (privado.mes_editavel(oficineiro_id, data)
         or revisao_status in ('devolvido', 'corrigido')
         or check_direcao in ('contestada', 'corrigida'))
  );

create or replace function privado.registro_editado()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if auth.uid() is not null and auth.uid() = old.oficineiro_id then
    new.revisao_status := case old.revisao_status when 'devolvido' then 'corrigido' when 'revisado' then null else old.revisao_status end;
    new.revisao_obs := old.revisao_obs;
    new.revisado_por := old.revisado_por;
    new.revisado_em := old.revisado_em;
    new.check_direcao := case old.check_direcao when 'contestada' then 'corrigida' else old.check_direcao end;
    new.check_motivo := old.check_motivo;
    new.check_por := old.check_por;
    new.check_em := old.check_em;
  end if;
  return new;
end;
$$;
revoke all on function privado.registro_editado() from public, anon;

create or replace function privado.conferir_aula(p_id bigint, p_confirmar boolean, p_motivo text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_a public.aulas_registro;
begin
  if privado.papel_atual() is distinct from 'direcao' or not privado.acesso_ok() then perform privado.negar(); end if;
  select * into v_a from public.aulas_registro where id = p_id for update;
  if v_a.id is null or v_a.escola_id is distinct from privado.escola_atual() then perform privado.negar(); end if;
  if v_a.situacao not in ('Realizada', 'Realizada parcialmente', 'Não realizada') then
    perform privado.invalido('a aula ainda não foi registrada pelo oficineiro');
  end if;
  if v_a.revisao_status = 'anulado' then perform privado.invalido('este registro foi anulado pela coordenação'); end if;
  if not coalesce(p_confirmar, false) and length(trim(coalesce(p_motivo, ''))) < 5 then
    perform privado.invalido('informe o motivo da contestação');
  end if;
  update public.aulas_registro
     set check_direcao = case when p_confirmar then 'ok' else 'contestada' end,
         check_motivo = case when p_confirmar then null else left(trim(p_motivo), 500) end,
         check_por = auth.uid(), check_em = now()
   where id = p_id;
end;
$$;

create or replace function privado.conferir_aulas(p_ids bigint[])
returns integer
language plpgsql security definer set search_path = ''
as $$
declare v_n integer;
begin
  if privado.papel_atual() is distinct from 'direcao' or not privado.acesso_ok() then perform privado.negar(); end if;
  if p_ids is null or cardinality(p_ids) = 0 then perform privado.invalido('nenhuma aula escolhida'); end if;
  if cardinality(p_ids) > 500 then perform privado.invalido('confirme no máximo 500 aulas de uma vez'); end if;
  update public.aulas_registro
     set check_direcao = 'ok', check_motivo = null, check_por = auth.uid(), check_em = now()
   where id = any (p_ids)
     and escola_id = privado.escola_atual()
     and situacao in ('Realizada', 'Realizada parcialmente', 'Não realizada')
     and revisao_status is distinct from 'anulado'
     and (check_direcao is null or check_direcao = 'corrigida');
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

create or replace function privado.devolver_relatorio(p_id bigint, p_motivo text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_r public.relatorios_mensais; v_papel public.papel := privado.papel_atual();
begin
  if not privado.acesso_ok() then perform privado.negar(); end if;
  if length(trim(coalesce(p_motivo, ''))) < 5 then perform privado.invalido('informe o motivo da devolução'); end if;
  select * into v_r from public.relatorios_mensais where id = p_id for update;
  if v_r.id is null then perform privado.negar(); end if;
  if (v_papel = 'direcao' and v_r.escola_id = privado.escola_atual() and v_r.status = 'fechado')
     or (v_papel = 'coordenador' and v_r.status = 'aprovado_direcao') then
    update public.relatorios_mensais
       set status = 'devolvido', motivo_devolucao = left(trim(p_motivo), 1000),
           devolvido_por = auth.uid(), devolvido_em = now(), devolvido_papel = v_papel::text
     where id = p_id;
  else
    perform privado.negar('este relatório não está na sua etapa de aprovação');
  end if;
end;
$$;

create or replace function privado.garantir_relatorios(p_competencia date)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_ini date := date_trunc('month', p_competencia)::date;
  v_fim date := (date_trunc('month', p_competencia) + interval '1 month')::date;
begin
  if v_ini >= date_trunc('month', privado.hoje())::date then return; end if;
  insert into public.relatorios_mensais (oficineiro_id, escola_id, competencia, status, fechado_em)
  select p.id, p.escola_id, v_ini, 'fechado', (v_fim::timestamp at time zone 'America/Sao_Paulo')
    from public.perfis p
   where p.papel::text = 'oficineiro'
     and p.escola_id is not null
     and privado.ve_escola(p.escola_id)
     and (exists (select 1 from public.presencas x where x.oficineiro_id = p.id and x.data >= v_ini and x.data < v_fim)
          or exists (select 1 from public.aulas_registro x where x.oficineiro_id = p.id and x.data >= v_ini and x.data < v_fim)
          or exists (select 1 from public.grade_aulas g
                      where g.oficineiro_id = p.id and g.ano_letivo = extract(year from v_ini)
                        and g.criado_em < (v_fim::timestamp at time zone 'America/Sao_Paulo')))
  on conflict (oficineiro_id, competencia) do nothing;
end;
$$;

create or replace function privado.relatorios_escola(p_competencia date)
returns table (
  id bigint, oficineiro_id uuid, oficineiro text, escola_id smallint, escola text,
  competencia date, status text, fechado_em timestamptz,
  direcao_em timestamptz, direcao_nome text, coordenacao_em timestamptz, coordenacao_nome text,
  devolvido_em timestamptz, devolvido_nome text, devolvido_papel text, motivo_devolucao text,
  dias_presenca integer, validos_min integer, registradas integer, realizadas integer, nao_realizadas integer,
  confirmadas integer, contestadas integer, estudantes integer
)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ini date := date_trunc('month', coalesce(p_competencia, privado.hoje()))::date;
  v_fim date := (date_trunc('month', coalesce(p_competencia, privado.hoje())) + interval '1 month')::date;
begin
  if not privado.acesso_ok() or privado.papel_atual() not in ('direcao', 'coordenador', 'gerente', 'analista') then
    perform privado.negar();
  end if;
  perform privado.garantir_relatorios(v_ini);
  return query
  select r.id, r.oficineiro_id, o.nome, r.escola_id, e.nome,
         r.competencia, r.status, r.fechado_em,
         r.direcao_em, pd.nome, r.coordenacao_em, pc.nome,
         r.devolvido_em, pv.nome, pv.papel::text, r.motivo_devolucao,
         (select count(distinct x.data)::integer from public.presencas x
           where x.oficineiro_id = r.oficineiro_id and x.data >= v_ini and x.data < v_fim and x.fim is not null),
         (select coalesce(sum(case when x.fim is null or x.conferencia_status = 'nao_conferida' then 0
                                   else least(coalesce(x.trabalhado_min, 0), coalesce(x.previsto_min, 480))
                                        + coalesce(x.compensacao_min, 0)
                                        + case when x.excedente_status = 'autorizado' then coalesce(x.excedente_min, 0) else 0 end
                              end), 0)::integer
            from public.presencas x
           where x.oficineiro_id = r.oficineiro_id and x.data >= v_ini and x.data < v_fim),
         a.registradas, a.realizadas, a.nao_realizadas, a.confirmadas, a.contestadas, a.estudantes
    from public.relatorios_mensais r
    join public.perfis o on o.id = r.oficineiro_id
    join public.escolas e on e.id = r.escola_id
    left join public.perfis pd on pd.id = r.direcao_por
    left join public.perfis pc on pc.id = r.coordenacao_por
    left join public.perfis pv on pv.id = r.devolvido_por
    cross join lateral (
      select count(*) filter (where x.situacao in ('Realizada', 'Realizada parcialmente', 'Não realizada'))::integer as registradas,
             count(*) filter (where x.situacao in ('Realizada', 'Realizada parcialmente'))::integer as realizadas,
             count(*) filter (where x.situacao = 'Não realizada')::integer as nao_realizadas,
             count(*) filter (where x.check_direcao = 'ok')::integer as confirmadas,
             count(*) filter (where x.check_direcao = 'contestada')::integer as contestadas,
             coalesce(sum(x.presentes) filter (where x.situacao in ('Realizada', 'Realizada parcialmente')), 0)::integer as estudantes
        from public.aulas_registro x
       where x.oficineiro_id = r.oficineiro_id and x.data >= v_ini and x.data < v_fim
         and x.revisao_status is distinct from 'anulado'
    ) a
   where r.competencia = v_ini
     and privado.ve_escola(r.escola_id)
   order by e.sigla, o.nome;
end;
$$;

create or replace function public.conferir_aulas(p_ids bigint[])
returns integer language sql security invoker set search_path = ''
as $$ select privado.conferir_aulas(p_ids) $$;

create or replace function public.relatorios_escola(p_competencia date)
returns table (
  id bigint, oficineiro_id uuid, oficineiro text, escola_id smallint, escola text,
  competencia date, status text, fechado_em timestamptz,
  direcao_em timestamptz, direcao_nome text, coordenacao_em timestamptz, coordenacao_nome text,
  devolvido_em timestamptz, devolvido_nome text, devolvido_papel text, motivo_devolucao text,
  dias_presenca integer, validos_min integer, registradas integer, realizadas integer, nao_realizadas integer,
  confirmadas integer, contestadas integer, estudantes integer
)
language sql security invoker set search_path = ''
as $$ select * from privado.relatorios_escola(p_competencia) $$;

revoke all on function
  privado.conferir_aula(bigint, boolean, text), privado.conferir_aulas(bigint[]),
  privado.devolver_relatorio(bigint, text), privado.garantir_relatorios(date), privado.relatorios_escola(date),
  public.conferir_aulas(bigint[]), public.relatorios_escola(date)
  from public, anon;
grant execute on function
  privado.conferir_aula(bigint, boolean, text), privado.conferir_aulas(bigint[]),
  privado.devolver_relatorio(bigint, text), privado.garantir_relatorios(date), privado.relatorios_escola(date),
  public.conferir_aulas(bigint[]), public.relatorios_escola(date)
  to authenticated;
revoke all on function privado.garantir_relatorios(date) from authenticated;
