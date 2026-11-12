create table if not exists public.folgas (
  id            bigint generated always as identity primary key,
  oficineiro_id uuid not null references public.perfis(id),
  escola_id     smallint not null references public.escolas(id),
  data          date not null,
  minutos       integer not null check (minutos between 1 and 480),
  observacao    text check (length(observacao) <= 500),
  status        text not null default 'aguardando' check (status in ('aguardando', 'aprovada', 'recusada', 'cancelada')),
  pedido_em     timestamptz not null default now(),
  decidido_por  uuid references public.perfis(id),
  decidido_em   timestamptz,
  decisao_obs   text check (length(decisao_obs) <= 500)
);
create index if not exists folgas_oficineiro_data_idx on public.folgas (oficineiro_id, data);
create index if not exists folgas_escola_data_idx on public.folgas (escola_id, data);
alter table public.folgas enable row level security;
revoke all on public.folgas from anon, authenticated;
grant select on public.folgas to authenticated;
drop policy if exists folgas_ler on public.folgas;
create policy folgas_ler on public.folgas for select to authenticated
  using (privado.ve_escola(escola_id)
         and ((select privado.papel_atual()) in ('direcao', 'coordenador')
              or oficineiro_id = (select auth.uid())));
drop trigger if exists auditoria on public.folgas;
create trigger auditoria after insert or update or delete on public.folgas
  for each row execute function auditoria.trigger_linha();

create or replace function privado.calcular_dia(p_id bigint)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_p public.presencas;
  v_trab integer;
  v_prev integer;
  v_dif integer;
  v_disp integer;
  v_comp integer := 0;
  v_exc integer := 0;
  v_def integer := 0;
begin
  select * into v_p from public.presencas where id = p_id for update;
  if v_p.id is null or v_p.fim is null then return; end if;
  v_prev := privado.minutos_previstos(v_p.data);
  if v_p.ponto and (v_p.pausa_inicio is null or v_p.pausa_fim is null) then
    update public.presencas
       set trabalhado_min = null, previsto_min = v_prev, compensacao_min = 0,
           excedente_min = 0, excedente_status = 'dentro', deficit_min = 0, deficit_status = 'dentro'
     where id = v_p.id;
    return;
  end if;
  v_trab := privado.minutos_trabalhados(v_p.inicio, v_p.fim, v_p.pausa_inicio, v_p.pausa_fim);
  v_dif := v_trab - v_prev;
  if v_dif > 15 then
    if not v_p.ponto then
      select coalesce(sum(d.deficit_min), 0) into v_disp
        from public.presencas d
       where d.oficineiro_id = v_p.oficineiro_id and d.compensar_em = v_p.data and d.id <> v_p.id
         and d.deficit_status in ('aguardando', 'autorizado');
      v_comp := least(v_dif, v_disp);
    end if;
    v_exc := v_dif - v_comp;
    if v_exc <= 15 then v_exc := 0; end if;
  elsif v_dif < -15 and not v_p.ponto then
    v_def := -v_dif;
  end if;
  update public.presencas
     set trabalhado_min = v_trab,
         previsto_min = v_prev,
         compensacao_min = v_comp,
         excedente_min = v_exc,
         excedente_status = case when v_exc = 0 then 'dentro'
                                 when excedente_status in ('aguardando', 'autorizado', 'nao') and excedente_min = v_exc then excedente_status
                                 when v_p.ponto then 'aguardando'
                                 else 'pendente' end,
         deficit_min = v_def,
         deficit_status = case when v_def = 0 then 'dentro'
                               when deficit_status in ('aguardando', 'autorizado', 'nao') and deficit_min = v_def then deficit_status
                               else 'pendente' end
   where id = v_p.id;
end;
$$;

create or replace function privado.horas_validas(p_oficineiro uuid, p_ini date, p_fim date)
returns integer
language sql stable security definer set search_path = ''
as $$
  with p as (
    select x.data,
           x.ponto,
           coalesce(x.previsto_min, privado.minutos_previstos(x.data)) as prev,
           case when x.fim is null or x.conferencia_status = 'nao_conferida' then 0
                when x.ponto and x.conferencia is not null and x.conferencia_status <> 'conferida' then 0
                when x.ponto then least(coalesce(x.trabalhado_min, 0), coalesce(x.previsto_min, 480))
                else least(coalesce(x.trabalhado_min, 0), coalesce(x.previsto_min, 480))
                     + coalesce(x.compensacao_min, 0)
                     + case when x.excedente_status = 'autorizado' then coalesce(x.excedente_min, 0) else 0 end
           end as v
      from public.presencas x
     where x.oficineiro_id = p_oficineiro and x.data between p_ini and p_fim
  ),
  f as (
    select g.data, sum(g.minutos)::integer as m
      from public.folgas g
     where g.oficineiro_id = p_oficineiro and g.status = 'aprovada' and g.data between p_ini and p_fim
     group by g.data
  )
  select coalesce(sum(case when p.ponto is false then p.v
                           else least(coalesce(p.prev, privado.minutos_previstos(coalesce(p.data, f.data))),
                                      coalesce(p.v, 0) + coalesce(f.m, 0)) end), 0)::integer
    from p full join f on f.data = p.data;
$$;

create or replace function privado.banco_do(p_oficineiro uuid, p_competencia date)
returns jsonb
language sql stable security definer set search_path = ''
as $$
  with c as (select privado.ciclo_inicio(p_competencia) as ini, privado.ciclo_fim(p_competencia) as fim),
  e as (
    select coalesce(sum(x.excedente_min) filter (where x.excedente_status = 'autorizado'), 0)::integer as gerado,
           coalesce(sum(x.excedente_min) filter (where x.excedente_status = 'aguardando'), 0)::integer as aguardando,
           coalesce(sum(x.excedente_min) filter (where x.excedente_status = 'nao'), 0)::integer as reprovado
      from public.presencas x, c
     where x.oficineiro_id = p_oficineiro and x.ponto and x.data between c.ini and c.fim
  ),
  f as (
    select coalesce(sum(g.minutos) filter (where g.status = 'aprovada'), 0)::integer as compensado,
           coalesce(sum(g.minutos) filter (where g.status = 'aguardando'), 0)::integer as pendente
      from public.folgas g, c
     where g.oficineiro_id = p_oficineiro and g.data between c.ini and c.fim
  )
  select jsonb_build_object(
           'competencia', p_competencia, 'inicio', c.ini, 'fim', c.fim,
           'gerado', e.gerado, 'aguardando', e.aguardando, 'reprovado', e.reprovado,
           'compensado', f.compensado, 'folga_pendente', f.pendente,
           'saldo', greatest(0, e.gerado - f.compensado),
           'disponivel', greatest(0, e.gerado - f.compensado - f.pendente),
           'fechado', c.fim < privado.hoje(),
           'zerado', case when c.fim < privado.hoje() then greatest(0, e.gerado - f.compensado) else 0 end)
    from c, e, f;
$$;

create or replace function privado.banco_horas(p_competencia date)
returns table(oficineiro_id uuid, nome text, escola_id smallint, banco jsonb)
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_comp date := case when p_competencia is null then privado.ciclo_de(privado.hoje())
                      else date_trunc('month', p_competencia)::date end;
begin
  if not privado.acesso_ok() or privado.papel_atual() not in ('oficineiro', 'direcao', 'coordenador') then
    perform privado.negar();
  end if;
  return query
  select p.id, p.nome, p.escola_id, privado.banco_do(p.id, v_comp)
    from public.perfis p
   where p.papel = 'oficineiro' and p.ativo
     and privado.ve_escola(p.escola_id)
     and (privado.papel_atual() <> 'oficineiro' or p.id = auth.uid())
   order by p.nome;
end;
$$;

create or replace function privado.pedir_folga(p_data date, p_minutos integer, p_observacao text default null)
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_comp date;
  v_banco jsonb;
  v_dia integer;
  v_id bigint;
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  if p_data is null or privado.ciclo_de(p_data) <> privado.ciclo_de(privado.hoje()) then
    perform privado.invalido('a folga precisa ser tirada dentro do ciclo atual');
  end if;
  v_comp := privado.ciclo_de(p_data);
  if exists (select 1 from public.relatorios_mensais r
              where r.oficineiro_id = v_uid and r.competencia = v_comp and r.status <> 'devolvido') then
    perform privado.invalido('ciclo fechado: peça a devolução do relatório');
  end if;
  if privado.minutos_previstos(p_data) = 0 then perform privado.invalido('escolha um dia letivo para a folga'); end if;
  if p_minutos is null or p_minutos < 1 or p_minutos > 480 then perform privado.invalido('informe as horas de folga, até 8 horas por dia'); end if;
  v_banco := privado.banco_do(v_uid, v_comp);
  if p_minutos > (v_banco ->> 'disponivel')::integer then perform privado.invalido('saldo do banco de horas insuficiente para esta folga'); end if;
  select coalesce(sum(minutos), 0) into v_dia from public.folgas
   where oficineiro_id = v_uid and data = p_data and status in ('aguardando', 'aprovada');
  if v_dia + p_minutos > 480 then perform privado.invalido('a folga do dia não pode passar de 8 horas'); end if;
  insert into public.folgas (oficineiro_id, escola_id, data, minutos, observacao)
  values (v_uid, privado.escola_atual(), p_data, p_minutos, nullif(left(trim(coalesce(p_observacao, '')), 500), ''))
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function privado.cancelar_folga(p_id bigint)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  update public.folgas set status = 'cancelada'
   where id = p_id and oficineiro_id = auth.uid() and status = 'aguardando';
  if not found then perform privado.invalido('só é possível cancelar uma folga que ainda aguarda a direção'); end if;
end;
$$;

create or replace function privado.decidir_folga(p_id bigint, p_aprovar boolean, p_comentario text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_f public.folgas;
  v_banco jsonb;
begin
  if not privado.acesso_ok() or (privado.papel_atual() is distinct from 'direcao' and not privado.eh_admin()) then perform privado.negar(); end if;
  select * into v_f from public.folgas where id = p_id for update;
  if v_f.id is null or not privado.ve_escola(v_f.escola_id) then perform privado.invalido('folga não encontrada'); end if;
  if v_f.status <> 'aguardando' then perform privado.invalido('esta folga já foi decidida'); end if;
  if not coalesce(p_aprovar, false) and length(trim(coalesce(p_comentario, ''))) < 5 then
    perform privado.invalido('explique por que a folga foi recusada');
  end if;
  if coalesce(p_aprovar, false) then
    v_banco := privado.banco_do(v_f.oficineiro_id, privado.ciclo_de(v_f.data));
    if v_f.minutos > (v_banco ->> 'saldo')::integer then perform privado.invalido('o oficineiro não tem saldo suficiente no banco de horas'); end if;
  end if;
  update public.folgas
     set status = case when p_aprovar then 'aprovada' else 'recusada' end,
         decidido_por = auth.uid(), decidido_em = now(),
         decisao_obs = nullif(left(trim(coalesce(p_comentario, '')), 500), '')
   where id = p_id;
end;
$$;

create or replace function privado.decidir_marcacao(p_id bigint, p_aceitar boolean, p_comentario text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_p public.presencas;
begin
  if not privado.acesso_ok() or (privado.papel_atual() is distinct from 'direcao' and not privado.eh_admin()) then perform privado.negar(); end if;
  select * into v_p from public.presencas where id = p_id for update;
  if v_p.id is null or not privado.ve_escola(v_p.escola_id) then perform privado.invalido('presença não encontrada'); end if;
  if v_p.falta_status <> 'aguardando' then perform privado.invalido('não há justificativa de marcação aguardando decisão'); end if;
  if not coalesce(p_aceitar, false) and length(trim(coalesce(p_comentario, ''))) < 5 then
    perform privado.invalido('explique por que a justificativa foi recusada');
  end if;
  if coalesce(p_aceitar, false) then
    update public.presencas
       set pausa_inicio = coalesce(pausa_inicio, ((data + (falta_horarios ->> 'pausa')::time) at time zone 'America/Sao_Paulo')),
           pausa_fim = coalesce(pausa_fim, ((data + (falta_horarios ->> 'retorno')::time) at time zone 'America/Sao_Paulo')),
           fim = coalesce(fim, ((data + (falta_horarios ->> 'fim')::time) at time zone 'America/Sao_Paulo')),
           marcacoes_informadas = (select array_agg(k order by k) from jsonb_object_keys(falta_horarios) k),
           falta_status = 'conferido',
           falta_obs = nullif(left(trim(coalesce(p_comentario, '')), 500), ''),
           falta_decidido_por = auth.uid(), falta_decidido_em = now()
     where id = p_id;
    perform privado.calcular_dia(p_id);
  else
    update public.presencas
       set falta_status = 'nao',
           falta_obs = left(trim(p_comentario), 500),
           falta_decidido_por = auth.uid(), falta_decidido_em = now()
     where id = p_id;
  end if;
end;
$$;

create or replace function privado.conferir_presenca(p_id bigint, p_conferir boolean, p_comentario text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_p public.presencas;
begin
  if not privado.acesso_ok() or (privado.papel_atual() is distinct from 'direcao' and not privado.eh_admin()) then perform privado.negar(); end if;
  select * into v_p from public.presencas where id = p_id for update;
  if v_p.id is null or not privado.ve_escola(v_p.escola_id) then perform privado.invalido('presença não encontrada'); end if;
  if v_p.conferencia is null and not (not v_p.ponto and v_p.fim is null and v_p.data < privado.hoje()) then
    perform privado.invalido('esta presença não precisa de conferência');
  end if;
  if v_p.conferencia_status <> 'pendente' then perform privado.invalido('esta presença já foi conferida'); end if;
  if not coalesce(p_conferir, false) and length(trim(coalesce(p_comentario, ''))) < 5 then
    perform privado.invalido('explique por que a presença não foi conferida');
  end if;
  update public.presencas
     set conferencia_status = case when p_conferir then 'conferida' else 'nao_conferida' end,
         conferencia_obs = nullif(left(trim(coalesce(p_comentario, '')), 500), ''),
         conferido_por = auth.uid(),
         conferido_em = now()
   where id = p_id;
end;
$$;

update public.presencas
   set excedente_status = 'aguardando'
 where ponto and excedente_status = 'pendente' and excedente_min > 0;

create or replace function privado.relatorios_escola(p_competencia date)
returns table(id bigint, oficineiro_id uuid, oficineiro text, escola_id smallint, escola text, competencia date, status text, fechado_em timestamptz, direcao_em timestamptz, direcao_nome text, coordenacao_em timestamptz, coordenacao_nome text, devolvido_em timestamptz, devolvido_nome text, devolvido_papel text, motivo_devolucao text, dias_presenca integer, validos_min integer, registradas integer, realizadas integer, nao_realizadas integer, confirmadas integer, contestadas integer, estudantes integer)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_comp date := case when p_competencia is null then privado.ciclo_de(privado.hoje())
                      else date_trunc('month', p_competencia)::date end;
  v_ini date := privado.ciclo_inicio(v_comp);
  v_fim date := privado.ciclo_fim(v_comp) + 1;
begin
  if not privado.acesso_ok() or privado.papel_atual() not in ('direcao', 'coordenador', 'gerente', 'analista') then
    perform privado.negar();
  end if;
  perform privado.garantir_relatorios(v_comp);
  return query
  select r.id, r.oficineiro_id, o.nome, r.escola_id, e.nome,
         r.competencia, r.status, r.fechado_em,
         r.direcao_em, pd.nome, r.coordenacao_em, pc.nome,
         r.devolvido_em, pv.nome, pv.papel::text, r.motivo_devolucao,
         (select count(distinct x.data)::integer from public.presencas x
           where x.oficineiro_id = r.oficineiro_id and x.data >= v_ini and x.data < v_fim and x.fim is not null),
         privado.horas_validas(r.oficineiro_id, v_ini, v_fim - 1),
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
   where r.competencia = v_comp
     and privado.ve_escola(r.escola_id)
   order by e.sigla, o.nome;
end;
$$;


revoke all on function privado.horas_validas(uuid, date, date), privado.banco_do(uuid, date) from public, anon, authenticated;
revoke all on function privado.banco_horas(date), privado.pedir_folga(date, integer, text), privado.cancelar_folga(bigint),
  privado.decidir_folga(bigint, boolean, text) from public, anon;
grant execute on function privado.banco_horas(date), privado.pedir_folga(date, integer, text), privado.cancelar_folga(bigint),
  privado.decidir_folga(bigint, boolean, text) to authenticated;

create or replace function public.banco_horas(p_competencia date default null)
returns table(oficineiro_id uuid, nome text, escola_id smallint, banco jsonb)
language sql stable security invoker set search_path = ''
as $$ select b.oficineiro_id, b.nome, b.escola_id, b.banco from privado.banco_horas(p_competencia) b $$;

create or replace function public.pedir_folga(p_data date, p_minutos integer, p_observacao text default null)
returns bigint language sql security invoker set search_path = ''
as $$ select privado.pedir_folga(p_data, p_minutos, p_observacao) $$;

create or replace function public.cancelar_folga(p_id bigint)
returns void language sql security invoker set search_path = ''
as $$ select privado.cancelar_folga(p_id) $$;

create or replace function public.decidir_folga(p_id bigint, p_aprovar boolean, p_comentario text default null)
returns void language sql security invoker set search_path = ''
as $$ select privado.decidir_folga(p_id, p_aprovar, p_comentario) $$;

revoke all on function public.banco_horas(date), public.pedir_folga(date, integer, text), public.cancelar_folga(bigint),
  public.decidir_folga(bigint, boolean, text) from public, anon;
grant execute on function public.banco_horas(date), public.pedir_folga(date, integer, text), public.cancelar_folga(bigint),
  public.decidir_folga(bigint, boolean, text) to authenticated;
