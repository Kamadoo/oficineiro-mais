create table if not exists public.presenca_tentativas (
  id            bigint generated always as identity primary key,
  oficineiro_id uuid not null references public.perfis(id),
  escola_id     smallint references public.escolas(id),
  tipo          text not null check (tipo in ('entrada', 'saida_almoco', 'retorno_almoco', 'saida')),
  tentado_em    timestamptz not null default now(),
  precisao_m    integer check (precisao_m between 0 and 100000),
  distancia_m   integer check (distancia_m >= 0),
  motivo        text not null check (length(motivo) <= 120)
);
create index if not exists presenca_tentativas_oficineiro_idx on public.presenca_tentativas (oficineiro_id, tentado_em);
alter table public.presenca_tentativas enable row level security;
revoke all on public.presenca_tentativas from anon, authenticated;
grant select on public.presenca_tentativas to authenticated;
drop policy if exists presenca_tentativas_ler on public.presenca_tentativas;
create policy presenca_tentativas_ler on public.presenca_tentativas for select to authenticated
  using (oficineiro_id = (select auth.uid())
         or ((select privado.papel_atual()) in ('coordenador', 'gerente') and privado.ve_escola(escola_id)));

create table if not exists public.presenca_ajustes (
  id             bigint generated always as identity primary key,
  oficineiro_id  uuid not null references public.perfis(id),
  escola_id      smallint not null references public.escolas(id),
  data           date not null,
  tipo           text not null check (tipo in ('falta', 'esquecimento', 'fora_raio', 'almoco', 'externa')),
  entrada        time,
  saida_almoco   time,
  retorno_almoco time,
  saida          time,
  motivo         text not null check (length(motivo) between 5 and 1000),
  status         text not null default 'em_analise' check (status in ('em_analise', 'aprovada', 'recusada')),
  pedido_em      timestamptz not null default now(),
  analisado_por  uuid references public.perfis(id),
  analisado_em   timestamptz,
  analise_obs    text check (length(analise_obs) <= 500),
  original       jsonb
);
create index if not exists presenca_ajustes_oficineiro_idx on public.presenca_ajustes (oficineiro_id, data);
create unique index if not exists presenca_ajustes_em_analise_uidx on public.presenca_ajustes (oficineiro_id, data) where status = 'em_analise';
alter table public.presenca_ajustes enable row level security;
revoke all on public.presenca_ajustes from anon, authenticated;
grant select on public.presenca_ajustes to authenticated;
drop policy if exists presenca_ajustes_ler on public.presenca_ajustes;
create policy presenca_ajustes_ler on public.presenca_ajustes for select to authenticated
  using (oficineiro_id = (select auth.uid())
         or ((select privado.papel_atual()) in ('coordenador', 'gerente') and privado.ve_escola(escola_id)));
drop trigger if exists auditoria on public.presenca_ajustes;
create trigger auditoria after insert or update or delete on public.presenca_ajustes
  for each row execute function auditoria.trigger_linha();

create table if not exists public.espelho_assinaturas (
  oficineiro_id uuid not null references public.perfis(id),
  competencia   date not null,
  assinado_em   timestamptz not null default now(),
  primary key (oficineiro_id, competencia)
);
alter table public.espelho_assinaturas enable row level security;
revoke all on public.espelho_assinaturas from anon, authenticated;
grant select on public.espelho_assinaturas to authenticated;
drop policy if exists espelho_assinaturas_ler on public.espelho_assinaturas;
create policy espelho_assinaturas_ler on public.espelho_assinaturas for select to authenticated
  using (oficineiro_id = (select auth.uid()) or (select privado.papel_atual()) in ('coordenador', 'gerente'));
drop trigger if exists auditoria on public.espelho_assinaturas;
create trigger auditoria after insert or update or delete on public.espelho_assinaturas
  for each row execute function auditoria.trigger_linha();

create or replace function privado.limite_dia()
returns integer
language sql immutable set search_path = ''
as $$ select 480 $$;

create or replace function privado.trabalhado_dia(p public.presencas, p_agora timestamptz default null)
returns integer
language sql stable set search_path = ''
as $$
  select case
           when p.inicio is null then 0
           when p.pausa_inicio is null then
             greatest(0, extract(epoch from (coalesce(p.fim, p_agora, p.inicio) - p.inicio)) / 60)::integer
           else
             greatest(0, extract(epoch from (p.pausa_inicio - p.inicio)) / 60)::integer
             + case when p.pausa_fim is null then 0
                    else greatest(0, extract(epoch from (coalesce(p.fim, p_agora, p.pausa_fim) - p.pausa_fim)) / 60)::integer end
         end
$$;

create or replace function privado.calcular_dia(p_id bigint)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_p public.presencas;
begin
  select * into v_p from public.presencas where id = p_id for update;
  if v_p.id is null then return; end if;
  update public.presencas
     set trabalhado_min = case when v_p.fim is not null and not (v_p.pausa_inicio is not null and v_p.pausa_fim is null)
                               then privado.trabalhado_dia(v_p) end,
         previsto_min = privado.limite_dia(), compensacao_min = 0,
         excedente_min = 0, excedente_status = 'dentro', deficit_min = 0, deficit_status = 'dentro'
   where id = p_id;
end;
$$;

create or replace function privado.proxima_marcacao(p public.presencas)
returns text
language sql immutable set search_path = ''
as $$
  select case
           when p.id is null then 'entrada'
           when p.fim is not null then null
           when p.pausa_inicio is null then 'saida_almoco'
           when p.pausa_fim is null then 'retorno_almoco'
           else 'saida'
         end
$$;

create or replace function privado.jornada_aberta(p_oficineiro uuid)
returns public.presencas
language sql stable security definer set search_path = ''
as $$
  select p.* from public.presencas p
   where p.oficineiro_id = p_oficineiro and p.fim is null and p.inicio > now() - interval '16 hours'
   order by p.inicio desc limit 1
$$;

create or replace function privado.oficinas_do_dia(p_oficineiro uuid, p_data date)
returns text
language sql stable security definer set search_path = ''
as $$
  select string_agg(distinct coalesce(nullif(g.oficina, ''), g.componente), ' · ')
    from public.grade_aulas g
   where g.oficineiro_id = p_oficineiro and g.ano_letivo = extract(year from p_data)
     and g.dia_semana = extract(isodow from p_data) and privado.minutos_previstos(p_data) > 0
$$;

create or replace function privado.marcar_presenca(p_tipo text, p_lat double precision, p_lng double precision, p_precisao integer default null)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_esc public.escolas;
  v_p public.presencas;
  v_prox text;
  v_dist integer;
  v_prec integer := case when p_precisao between 0 and 100000 then p_precisao end;
  v_motivo text;
  v_agora timestamptz := clock_timestamp();
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  if p_tipo not in ('entrada', 'saida_almoco', 'retorno_almoco', 'saida') then perform privado.invalido('marcação inválida'); end if;
  if (p_lat is null) <> (p_lng is null) or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    perform privado.invalido('localização inválida');
  end if;

  v_p := privado.jornada_aberta(v_uid);
  if v_p.id is null and exists (select 1 from public.presencas
                                 where oficineiro_id = v_uid and data = (v_agora at time zone 'America/Sao_Paulo')::date) then
    perform privado.invalido('a jornada de hoje já foi encerrada');
  end if;
  v_prox := privado.proxima_marcacao(v_p);
  if not (p_tipo = v_prox or (p_tipo = 'saida' and v_prox = 'saida_almoco')) then
    perform privado.invalido('esta marcação não é a próxima da sequência');
  end if;

  select * into v_esc from public.escolas where id = coalesce(v_p.escola_id, privado.escola_atual());
  if v_esc.id is null then perform privado.invalido('você não está vinculado a uma escola'); end if;
  if p_lat is null then
    v_motivo := 'Sem localização';
  elsif v_esc.latitude is null or v_esc.longitude is null then
    v_motivo := 'Escola sem localização cadastrada';
  else
    v_dist := privado.distancia_m(p_lat, p_lng, v_esc.latitude, v_esc.longitude);
    if v_prec is not null and v_prec > greatest(v_esc.raio_m, 100) then
      v_motivo := 'Localização imprecisa';
    elsif v_dist > v_esc.raio_m then
      v_motivo := 'Fora do raio da escola';
    end if;
  end if;

  if v_motivo is not null then
    insert into public.presenca_tentativas (oficineiro_id, escola_id, tipo, precisao_m, distancia_m, motivo)
    values (v_uid, v_esc.id, p_tipo, v_prec, v_dist, v_motivo);
    return jsonb_build_object('aceita', false, 'motivo', v_motivo, 'distancia_m', v_dist, 'precisao_m', v_prec, 'raio_m', v_esc.raio_m);
  end if;

  if p_tipo = 'entrada' then
    insert into public.presencas (oficineiro_id, escola_id, data, inicio, distancia_inicio_m, horario_status, ponto)
    values (v_uid, v_esc.id, (v_agora at time zone 'America/Sao_Paulo')::date, v_agora, v_dist, 'dentro', true)
    returning * into v_p;
  elsif p_tipo = 'saida_almoco' then
    update public.presencas set pausa_inicio = v_agora where id = v_p.id returning * into v_p;
  elsif p_tipo = 'retorno_almoco' then
    update public.presencas set pausa_fim = v_agora where id = v_p.id returning * into v_p;
  else
    update public.presencas set fim = v_agora, distancia_fim_m = v_dist where id = v_p.id returning * into v_p;
    perform privado.calcular_dia(v_p.id);
  end if;

  insert into public.presenca_marcacoes (presenca_id, oficineiro_id, tipo, registrado_em, precisao_m, distancia_m, dentro_raio)
  values (v_p.id, v_uid, p_tipo, v_agora, v_prec, v_dist, true)
  on conflict (presenca_id, tipo) do update
     set registrado_em = excluded.registrado_em, recebido_em = now(), precisao_m = excluded.precisao_m,
         distancia_m = excluded.distancia_m, dentro_raio = true;

  return jsonb_build_object('aceita', true, 'tipo', p_tipo, 'em', v_agora, 'distancia_m', v_dist);
end;
$$;

create or replace function privado.minha_presenca_hoje()
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_p public.presencas;
  v_esc public.escolas;
  v_agora timestamptz := now();
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  v_p := privado.jornada_aberta(v_uid);
  if v_p.id is null then
    select * into v_p from public.presencas
     where oficineiro_id = v_uid and data = (v_agora at time zone 'America/Sao_Paulo')::date;
  end if;
  select * into v_esc from public.escolas where id = coalesce(v_p.escola_id, privado.escola_atual());
  return jsonb_build_object(
    'agora', v_agora,
    'data', coalesce(v_p.data, (v_agora at time zone 'America/Sao_Paulo')::date),
    'escola', v_esc.nome,
    'raio_m', v_esc.raio_m,
    'escola_localizada', v_esc.latitude is not null and v_esc.longitude is not null,
    'oficina', privado.oficinas_do_dia(v_uid, (v_agora at time zone 'America/Sao_Paulo')::date),
    'limite_min', privado.limite_dia(),
    'proxima', privado.proxima_marcacao(v_p),
    'trabalhado_min', privado.trabalhado_dia(v_p, v_agora),
    'marcacoes', coalesce((select jsonb_agg(jsonb_build_object('tipo', m.tipo, 'em', m.registrado_em, 'distancia_m', m.distancia_m)
                                            order by m.registrado_em)
                             from public.presenca_marcacoes m where m.presenca_id = v_p.id), '[]'::jsonb));
end;
$$;

create or replace function privado.espelho_dias(p_oficineiro uuid, p_ini date, p_fim date)
returns table(data date, entrada timestamptz, saida_almoco timestamptz, retorno_almoco timestamptz, saida timestamptz,
              trabalhado_min integer, contabilizado_min integer, nao_contabilizado_min integer, situacao text, ajuste text)
language sql stable security definer set search_path = ''
as $$
  with d as (
    select g::date as data from generate_series(p_ini, least(p_fim, privado.hoje()), interval '1 day') g
  )
  select d.data, p.inicio, p.pausa_inicio, p.pausa_fim, p.fim,
         case when p.fim is not null then privado.trabalhado_dia(p) end,
         case when p.fim is not null then least(privado.trabalhado_dia(p), privado.limite_dia()) end,
         case when p.fim is not null then greatest(0, privado.trabalhado_dia(p) - privado.limite_dia()) end,
         case when p.id is null then 'falta'
              when p.fim is null or (p.pausa_inicio is not null and p.pausa_fim is null) then 'pendente'
              when privado.trabalhado_dia(p) > privado.limite_dia() then 'acima_8h'
              else 'regular' end,
         (select a.status from public.presenca_ajustes a
           where a.oficineiro_id = p_oficineiro and a.data = d.data order by a.pedido_em desc limit 1)
    from d
    left join public.presencas p on p.oficineiro_id = p_oficineiro and p.data = d.data
   where p.id is not null
      or (d.data < privado.hoje() and privado.oficinas_do_dia(p_oficineiro, d.data) is not null)
   order by d.data desc
$$;

create or replace function privado.meu_espelho(p_competencia date default null)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_comp date := coalesce(date_trunc('month', p_competencia)::date, privado.ciclo_de(privado.hoje()));
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  return jsonb_build_object(
    'competencia', v_comp,
    'inicio', privado.ciclo_inicio(v_comp),
    'fim', privado.ciclo_fim(v_comp),
    'assinado_em', (select a.assinado_em from public.espelho_assinaturas a where a.oficineiro_id = v_uid and a.competencia = v_comp),
    'dias', coalesce((select jsonb_agg(to_jsonb(x)) from privado.espelho_dias(v_uid, privado.ciclo_inicio(v_comp), privado.ciclo_fim(v_comp)) x), '[]'::jsonb));
end;
$$;

create or replace function privado.assinar_espelho(p_competencia date)
returns timestamptz
language plpgsql security definer set search_path = ''
as $$
declare
  v_comp date := date_trunc('month', p_competencia)::date;
  v_em timestamptz;
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  if p_competencia is null or privado.ciclo_inicio(v_comp) > privado.hoje() then perform privado.invalido('escolha um mês já iniciado'); end if;
  insert into public.espelho_assinaturas (oficineiro_id, competencia) values (auth.uid(), v_comp)
  on conflict (oficineiro_id, competencia) do nothing
  returning assinado_em into v_em;
  if v_em is null then perform privado.invalido('este espelho já foi assinado'); end if;
  return v_em;
end;
$$;

create or replace function privado.horarios_ajustados(p public.presencas, p_data date, p_entrada time, p_saida_almoco time,
                                                      p_retorno_almoco time, p_saida time)
returns public.presencas
language plpgsql stable set search_path = ''
as $$
declare
  v public.presencas := p;
  v_tz text := 'America/Sao_Paulo';
begin
  v.data := p_data;
  if p_entrada is not null then v.inicio := (p_data + p_entrada) at time zone v_tz; end if;
  if p_saida_almoco is not null then v.pausa_inicio := (p_data + p_saida_almoco) at time zone v_tz; end if;
  if p_retorno_almoco is not null then v.pausa_fim := (p_data + p_retorno_almoco) at time zone v_tz; end if;
  if p_saida is not null then v.fim := (p_data + p_saida) at time zone v_tz; end if;
  if v.inicio is null then perform privado.invalido('informe o horário de entrada'); end if;
  if (v.pausa_inicio is null) <> (v.pausa_fim is null) then perform privado.invalido('informe a saída e a volta do almoço juntas'); end if;
  if v.pausa_inicio is not null and not (v.inicio < v.pausa_inicio and v.pausa_inicio <= v.pausa_fim) then
    perform privado.invalido('os horários do almoço precisam ficar entre a entrada e a saída');
  end if;
  if v.fim is not null and v.fim <= coalesce(v.pausa_fim, v.inicio) then perform privado.invalido('a saída precisa ser depois dos outros horários'); end if;
  if v.fim is not null and privado.trabalhado_dia(v) > privado.limite_dia() then
    perform privado.invalido('com estes horários o dia passa de 8 horas trabalhadas');
  end if;
  return v;
end;
$$;

create or replace function privado.solicitar_ajuste(p_tipo text, p_data date, p_entrada time, p_saida_almoco time,
                                                    p_retorno_almoco time, p_saida time, p_motivo text)
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_p public.presencas;
  v_id bigint;
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  if p_tipo not in ('falta', 'esquecimento', 'fora_raio', 'almoco', 'externa') then perform privado.invalido('tipo de solicitação inválido'); end if;
  if p_data is null or p_data > privado.hoje() then perform privado.invalido('escolha uma data até hoje'); end if;
  if p_data < privado.ciclo_inicio(privado.ciclo_de(privado.hoje())) then
    perform privado.invalido('o prazo para justificar este dia terminou no fechamento do ciclo');
  end if;
  if length(trim(coalesce(p_motivo, ''))) < 5 then perform privado.invalido('explique o motivo da solicitação'); end if;
  if p_tipo <> 'falta' then
    select * into v_p from public.presencas where oficineiro_id = v_uid and data = p_data;
    perform privado.horarios_ajustados(v_p, p_data, p_entrada, p_saida_almoco, p_retorno_almoco, p_saida);
  end if;
  if exists (select 1 from public.presenca_ajustes where oficineiro_id = v_uid and data = p_data and status = 'em_analise') then
    perform privado.invalido('já existe uma solicitação em análise para este dia');
  end if;
  insert into public.presenca_ajustes (oficineiro_id, escola_id, data, tipo, entrada, saida_almoco, retorno_almoco, saida, motivo)
  values (v_uid, coalesce(v_p.escola_id, privado.escola_atual()), p_data, p_tipo,
          case when p_tipo <> 'falta' then p_entrada end, case when p_tipo <> 'falta' then p_saida_almoco end,
          case when p_tipo <> 'falta' then p_retorno_almoco end, case when p_tipo <> 'falta' then p_saida end,
          left(trim(p_motivo), 1000))
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function privado.decidir_ajuste(p_id bigint, p_aprovar boolean, p_obs text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_a public.presenca_ajustes;
  v_p public.presencas;
  v_n public.presencas;
begin
  if not privado.acesso_ok() or privado.papel_atual() is distinct from 'coordenador' then perform privado.negar(); end if;
  select * into v_a from public.presenca_ajustes where id = p_id for update;
  if v_a.id is null or not privado.ve_escola(v_a.escola_id) then perform privado.invalido('solicitação não encontrada'); end if;
  if v_a.status <> 'em_analise' then perform privado.invalido('esta solicitação já foi analisada'); end if;
  if not coalesce(p_aprovar, false) and length(trim(coalesce(p_obs, ''))) < 5 then
    perform privado.invalido('explique por que a solicitação foi recusada');
  end if;
  if coalesce(p_aprovar, false) and v_a.tipo <> 'falta' then
    select * into v_p from public.presencas where oficineiro_id = v_a.oficineiro_id and data = v_a.data for update;
    v_n := privado.horarios_ajustados(v_p, v_a.data, v_a.entrada, v_a.saida_almoco, v_a.retorno_almoco, v_a.saida);
    if v_p.id is null then
      insert into public.presencas (oficineiro_id, escola_id, data, inicio, pausa_inicio, pausa_fim, fim, horario_status, ponto)
      values (v_a.oficineiro_id, v_a.escola_id, v_a.data, v_n.inicio, v_n.pausa_inicio, v_n.pausa_fim, v_n.fim, 'dentro', true)
      returning * into v_n;
    else
      update public.presencas
         set inicio = v_n.inicio, pausa_inicio = v_n.pausa_inicio, pausa_fim = v_n.pausa_fim, fim = v_n.fim
       where id = v_p.id
      returning * into v_n;
    end if;
    perform privado.calcular_dia(v_n.id);
  end if;
  update public.presenca_ajustes
     set status = case when p_aprovar then 'aprovada' else 'recusada' end,
         analisado_por = auth.uid(), analisado_em = now(),
         analise_obs = nullif(left(trim(coalesce(p_obs, '')), 500), ''),
         original = case when p_aprovar and v_p.id is not null
                         then jsonb_build_object('entrada', v_p.inicio, 'saida_almoco', v_p.pausa_inicio,
                                                 'retorno_almoco', v_p.pausa_fim, 'saida', v_p.fim) end
   where id = p_id;
end;
$$;

create or replace function privado.ajustes_presenca(p_status text default null)
returns table(id bigint, oficineiro_id uuid, nome text, escola_id smallint, escola text, data date, tipo text,
              entrada time, saida_almoco time, retorno_almoco time, saida time, motivo text, status text,
              pedido_em timestamptz, analisado_em timestamptz, analise_obs text)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not privado.acesso_ok() or privado.papel_atual() not in ('oficineiro', 'coordenador', 'gerente') then perform privado.negar(); end if;
  return query
  select a.id, a.oficineiro_id, o.nome, a.escola_id, e.nome, a.data, a.tipo, a.entrada, a.saida_almoco, a.retorno_almoco,
         a.saida, a.motivo, a.status, a.pedido_em, a.analisado_em, a.analise_obs
    from public.presenca_ajustes a
    join public.perfis o on o.id = a.oficineiro_id
    join public.escolas e on e.id = a.escola_id
   where (p_status is null or a.status = p_status)
     and case when privado.papel_atual() = 'oficineiro' then a.oficineiro_id = auth.uid() else privado.ve_escola(a.escola_id) end
   order by a.pedido_em desc
   limit 300;
end;
$$;

create or replace function privado.painel_presenca()
returns table(oficineiro_id uuid, nome text, escola_id smallint, escola text, turno text, oficina text,
              entrada timestamptz, saida_almoco timestamptz, retorno_almoco timestamptz, saida timestamptz,
              trabalhado_min integer, situacao text, escalado boolean, atualizado_em timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_agora timestamptz := now();
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if not privado.acesso_ok() or privado.papel_atual() not in ('coordenador', 'gerente') then perform privado.negar(); end if;
  return query
  select o.id, o.nome, e.id, e.nome, o.turno, privado.oficinas_do_dia(o.id, v_hoje),
         p.inicio, p.pausa_inicio, p.pausa_fim, p.fim,
         case when p.id is null then 0 else privado.trabalhado_dia(p, v_agora) end,
         case when p.id is null then 'sem_registro'
              when p.fim is not null then 'encerrado'
              when p.pausa_inicio is not null and p.pausa_fim is null then 'almoco'
              when privado.trabalhado_dia(p, v_agora) >= privado.limite_dia() - 30 then 'perto_limite'
              else 'trabalhando' end,
         privado.oficinas_do_dia(o.id, v_hoje) is not null,
         v_agora
    from public.perfis o
    join public.escolas e on e.id = o.escola_id
    left join lateral (
      select x.* from public.presencas x
       where x.oficineiro_id = o.id and (x.data = v_hoje or (x.fim is null and x.inicio > v_agora - interval '16 hours'))
       order by x.inicio desc limit 1
    ) p on true
   where o.papel = 'oficineiro' and o.ativo and privado.ve_escola(o.escola_id)
   order by e.nome, o.nome;
end;
$$;

create or replace function privado.horas_validas(p_oficineiro uuid, p_ini date, p_fim date)
returns integer
language sql stable security definer set search_path = ''
as $$
  select coalesce(sum(least(privado.trabalhado_dia(x), privado.limite_dia())), 0)::integer
    from public.presencas x
   where x.oficineiro_id = p_oficineiro and x.data between p_ini and p_fim and x.fim is not null
$$;

revoke all on function privado.limite_dia(), privado.trabalhado_dia(public.presencas, timestamptz), privado.calcular_dia(bigint),
  privado.proxima_marcacao(public.presencas), privado.jornada_aberta(uuid), privado.oficinas_do_dia(uuid, date),
  privado.espelho_dias(uuid, date, date), privado.horarios_ajustados(public.presencas, date, time, time, time, time)
  from public, anon, authenticated;
revoke all on function privado.marcar_presenca(text, double precision, double precision, integer), privado.minha_presenca_hoje(),
  privado.meu_espelho(date), privado.assinar_espelho(date), privado.solicitar_ajuste(text, date, time, time, time, time, text),
  privado.decidir_ajuste(bigint, boolean, text), privado.ajustes_presenca(text), privado.painel_presenca() from public, anon;
grant execute on function privado.marcar_presenca(text, double precision, double precision, integer), privado.minha_presenca_hoje(),
  privado.meu_espelho(date), privado.assinar_espelho(date), privado.solicitar_ajuste(text, date, time, time, time, time, text),
  privado.decidir_ajuste(bigint, boolean, text), privado.ajustes_presenca(text), privado.painel_presenca() to authenticated;

create or replace function public.marcar_presenca(p_tipo text, p_lat double precision, p_lng double precision, p_precisao integer default null)
returns jsonb language sql security invoker set search_path = ''
as $$ select privado.marcar_presenca(p_tipo, p_lat, p_lng, p_precisao) $$;

create or replace function public.minha_presenca_hoje()
returns jsonb language sql stable security invoker set search_path = ''
as $$ select privado.minha_presenca_hoje() $$;

create or replace function public.meu_espelho(p_competencia date default null)
returns jsonb language sql stable security invoker set search_path = ''
as $$ select privado.meu_espelho(p_competencia) $$;

create or replace function public.assinar_espelho(p_competencia date)
returns timestamptz language sql security invoker set search_path = ''
as $$ select privado.assinar_espelho(p_competencia) $$;

create or replace function public.solicitar_ajuste(p_tipo text, p_data date, p_entrada time default null, p_saida_almoco time default null,
                                                   p_retorno_almoco time default null, p_saida time default null, p_motivo text default null)
returns bigint language sql security invoker set search_path = ''
as $$ select privado.solicitar_ajuste(p_tipo, p_data, p_entrada, p_saida_almoco, p_retorno_almoco, p_saida, p_motivo) $$;

create or replace function public.decidir_ajuste(p_id bigint, p_aprovar boolean, p_obs text default null)
returns void language sql security invoker set search_path = ''
as $$ select privado.decidir_ajuste(p_id, p_aprovar, p_obs) $$;

create or replace function public.ajustes_presenca(p_status text default null)
returns table(id bigint, oficineiro_id uuid, nome text, escola_id smallint, escola text, data date, tipo text,
              entrada time, saida_almoco time, retorno_almoco time, saida time, motivo text, status text,
              pedido_em timestamptz, analisado_em timestamptz, analise_obs text)
language sql stable security invoker set search_path = ''
as $$ select * from privado.ajustes_presenca(p_status) $$;

create or replace function public.painel_presenca()
returns table(oficineiro_id uuid, nome text, escola_id smallint, escola text, turno text, oficina text,
              entrada timestamptz, saida_almoco timestamptz, retorno_almoco timestamptz, saida timestamptz,
              trabalhado_min integer, situacao text, escalado boolean, atualizado_em timestamptz)
language sql stable security invoker set search_path = ''
as $$ select * from privado.painel_presenca() $$;

revoke all on function public.marcar_presenca(text, double precision, double precision, integer), public.minha_presenca_hoje(),
  public.meu_espelho(date), public.assinar_espelho(date), public.solicitar_ajuste(text, date, time, time, time, time, text),
  public.decidir_ajuste(bigint, boolean, text), public.ajustes_presenca(text), public.painel_presenca() from public, anon;
grant execute on function public.marcar_presenca(text, double precision, double precision, integer), public.minha_presenca_hoje(),
  public.meu_espelho(date), public.assinar_espelho(date), public.solicitar_ajuste(text, date, time, time, time, time, text),
  public.decidir_ajuste(bigint, boolean, text), public.ajustes_presenca(text), public.painel_presenca() to authenticated;
