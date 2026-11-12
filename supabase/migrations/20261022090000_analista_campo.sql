alter table public.visitas_agenda drop constraint if exists visitas_agenda_origem_check;
alter table public.visitas_agenda add constraint visitas_agenda_origem_check
  check (origem in ('relatorio', 'mapa_calor', 'demanda', 'gerencia', 'analista'));
alter table public.visitas_agenda add column if not exists motivo_alteracao text check (length(motivo_alteracao) <= 300);
alter table public.visitas_agenda add column if not exists data_original date;
alter table public.visitas_agenda add column if not exists remarcada_em timestamptz;

create table if not exists public.presencas_analista (
  id                 bigint generated always as identity primary key,
  analista_id        uuid not null references public.perfis (id),
  escola_id          smallint not null references public.escolas (id),
  data               date not null,
  inicio             timestamptz not null,
  fim                timestamptz,
  distancia_inicio_m integer check (distancia_inicio_m >= 0),
  distancia_fim_m    integer check (distancia_fim_m >= 0),
  conferencia        text check (conferencia in ('Fora do raio', 'Sem localização', 'Escola sem localização')),
  agenda_id          bigint references public.visitas_agenda (id) on delete set null,
  observacao         text check (length(observacao) <= 300),
  check (fim is null or fim > inicio)
);
alter table public.presencas_analista drop constraint if exists presencas_analista_conferencia_check;
alter table public.presencas_analista add constraint presencas_analista_conferencia_check
  check (conferencia in ('Fora do raio', 'Sem localização', 'Escola sem localização', 'Encerrada em outro dia'));
create unique index if not exists presencas_analista_aberta on public.presencas_analista (analista_id) where fim is null;
create index if not exists presencas_analista_data on public.presencas_analista (analista_id, data);
create index if not exists presencas_analista_escola on public.presencas_analista (escola_id, data);
alter table public.presencas_analista enable row level security;
revoke all on public.presencas_analista from anon, authenticated;
grant select on public.presencas_analista to authenticated;
drop policy if exists presencas_analista_ler on public.presencas_analista;
create policy presencas_analista_ler on public.presencas_analista for select to authenticated
  using (
    (select privado.acesso_ok())
    and ((select privado.papel_atual()) in ('gerente', 'coordenador')
         or ((select privado.papel_atual()) = 'analista' and analista_id = (select auth.uid())))
  );
drop trigger if exists auditoria on public.presencas_analista;
create trigger auditoria after insert or update or delete on public.presencas_analista
  for each row execute function auditoria.trigger_linha();

alter table public.visitas add column if not exists agenda_id bigint references public.visitas_agenda (id) on delete set null;
alter table public.visitas add column if not exists presenca_id bigint references public.presencas_analista (id) on delete set null;
alter table public.visitas add column if not exists objetivo text check (objetivo in ('Sim', 'Parcialmente', 'Não'));
alter table public.visitas add column if not exists engajamento smallint check (engajamento between 1 and 5);
alter table public.visitas add column if not exists boas_praticas text check (length(boas_praticas) <= 1000);
alter table public.visitas add column if not exists dificuldades text check (length(dificuldades) <= 1000);
alter table public.visitas add column if not exists ocorrencias text check (length(ocorrencias) <= 200);
alter table public.visitas add column if not exists ocorrencia_obs text check (length(ocorrencia_obs) <= 1000);
alter table public.visitas add column if not exists editado_em timestamptz;
create index if not exists visitas_analista_data on public.visitas (analista_id, data);

create table if not exists public.visitas_historico (
  id        bigint generated always as identity primary key,
  visita_id bigint not null references public.visitas (id) on delete cascade,
  antes     jsonb not null,
  por       uuid references public.perfis (id),
  em        timestamptz not null default now()
);
create index if not exists visitas_historico_visita on public.visitas_historico (visita_id, em);
alter table public.visitas_historico enable row level security;
revoke all on public.visitas_historico from anon, authenticated;
grant select on public.visitas_historico to authenticated;
drop policy if exists visitas_historico_ler on public.visitas_historico;
create policy visitas_historico_ler on public.visitas_historico for select to authenticated
  using (
    (select privado.acesso_ok())
    and ((select privado.papel_atual()) in ('gerente', 'coordenador')
         or exists (select 1 from public.visitas v where v.id = visita_id and v.analista_id = (select auth.uid())))
  );

create or replace function privado.dia_de_visita(p_data date)
returns text
language sql stable security definer set search_path = ''
as $$
  select case
    when p_data is null then 'informe a data'
    when extract(isodow from p_data) > 5 then 'escolha um dia útil'
    when privado.feriado(p_data) then 'a data escolhida é feriado'
  end;
$$;

create or replace function privado.agendar_visita(
  p_analista uuid, p_escola smallint, p_data date, p_hora time, p_origem text,
  p_tipo text default null, p_foco text default null, p_orientacao text default null
)
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare v_a public.perfis; v_e public.escolas; v_id bigint; v_dia text;
begin
  if not privado.acesso_ok() or privado.papel_atual() not in ('gerente', 'coordenador') then perform privado.negar(); end if;
  select * into v_a from public.perfis where id = p_analista;
  if v_a.id is null or v_a.papel <> 'analista' or not v_a.ativo then perform privado.invalido('escolha um analista ativo'); end if;
  select * into v_e from public.escolas where id = p_escola;
  if v_e.id is null or v_e.ativa is false then perform privado.invalido('escolha uma escola ativa'); end if;
  if v_e.carteira_id is distinct from v_a.carteira_id then
    perform privado.invalido('esta escola não é da carteira deste analista');
  end if;
  if p_data is null or p_data < privado.hoje() or p_data > privado.hoje() + 180 then
    perform privado.invalido('escolha uma data entre hoje e os próximos 6 meses');
  end if;
  v_dia := privado.dia_de_visita(p_data);
  if v_dia is not null then perform privado.invalido(v_dia); end if;
  if coalesce(p_origem, '') not in ('relatorio', 'mapa_calor', 'demanda', 'gerencia') then
    perform privado.invalido('origem da visita inválida');
  end if;
  if exists (select 1 from public.visitas_agenda
              where analista_id = p_analista and escola_id = p_escola and data = p_data and status = 'agendada') then
    perform privado.invalido('este analista já tem visita agendada nesta escola neste dia');
  end if;
  insert into public.visitas_agenda (analista_id, escola_id, data, hora, origem, tipo, foco, orientacao, criada_por)
  values (p_analista, p_escola, p_data, p_hora, p_origem,
          nullif(left(trim(coalesce(p_tipo, '')), 80), ''),
          nullif(left(trim(coalesce(p_foco, '')), 120), ''),
          nullif(left(trim(coalesce(p_orientacao, '')), 1000), ''),
          auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function privado.agendar_minha_visita(
  p_escola smallint, p_data date, p_hora time, p_origem text,
  p_tipo text default null, p_foco text default null, p_orientacao text default null
)
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare v_e public.escolas; v_id bigint; v_dia text;
begin
  if not privado.acesso_ok() or privado.papel_atual() is distinct from 'analista' then perform privado.negar(); end if;
  select * into v_e from public.escolas where id = p_escola;
  if v_e.id is null or v_e.ativa is false then perform privado.invalido('escolha uma escola ativa'); end if;
  if not privado.ve_escola(p_escola) then perform privado.invalido('esta escola não é da sua carteira'); end if;
  if p_data is null or p_data < privado.hoje() or p_data > privado.hoje() + 180 then
    perform privado.invalido('escolha uma data entre hoje e os próximos 6 meses');
  end if;
  v_dia := privado.dia_de_visita(p_data);
  if v_dia is not null then perform privado.invalido(v_dia); end if;
  if coalesce(p_origem, '') not in ('demanda', 'analista') then perform privado.invalido('origem da visita inválida'); end if;
  if exists (select 1 from public.visitas_agenda
              where analista_id = auth.uid() and escola_id = p_escola and data = p_data and status = 'agendada') then
    perform privado.invalido('você já tem visita agendada nesta escola neste dia');
  end if;
  insert into public.visitas_agenda (analista_id, escola_id, data, hora, origem, tipo, foco, orientacao, criada_por)
  values (auth.uid(), p_escola, p_data, p_hora, p_origem,
          nullif(left(trim(coalesce(p_tipo, '')), 80), ''),
          nullif(left(trim(coalesce(p_foco, '')), 120), ''),
          nullif(left(trim(coalesce(p_orientacao, '')), 1000), ''),
          auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function privado.pode_mexer_agenda(v_ag public.visitas_agenda)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select privado.acesso_ok() and (
    privado.papel_atual() in ('gerente', 'coordenador')
    or (privado.papel_atual() = 'analista' and v_ag.analista_id = auth.uid() and v_ag.criada_por = auth.uid())
  );
$$;

create or replace function privado.remarcar_visita_agenda(p_id bigint, p_data date, p_hora time, p_motivo text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_ag public.visitas_agenda; v_dia text;
begin
  if not privado.acesso_ok() or privado.papel_atual() not in ('gerente', 'coordenador', 'analista') then perform privado.negar(); end if;
  select * into v_ag from public.visitas_agenda where id = p_id for update;
  if v_ag.id is null then perform privado.invalido('visita não encontrada'); end if;
  if not privado.pode_mexer_agenda(v_ag) then
    perform privado.negar('só quem vinculou esta visita pode remarcá-la');
  end if;
  if v_ag.status <> 'agendada' then perform privado.invalido('só visitas agendadas podem ser remarcadas'); end if;
  if p_data is null or p_data < privado.hoje() or p_data > privado.hoje() + 180 then
    perform privado.invalido('escolha uma data entre hoje e os próximos 6 meses');
  end if;
  v_dia := privado.dia_de_visita(p_data);
  if v_dia is not null then perform privado.invalido(v_dia); end if;
  if length(trim(coalesce(p_motivo, ''))) < 3 then perform privado.invalido('informe o motivo da remarcação'); end if;
  if p_data = v_ag.data and p_hora is not distinct from v_ag.hora then perform privado.invalido('escolha outra data ou horário'); end if;
  if exists (select 1 from public.visitas_agenda
              where analista_id = v_ag.analista_id and escola_id = v_ag.escola_id and data = p_data
                and status = 'agendada' and id <> p_id) then
    perform privado.invalido('já existe visita agendada nesta escola neste dia');
  end if;
  update public.visitas_agenda
     set data_original = coalesce(data_original, data), data = p_data, hora = p_hora, remarcada_em = now(),
         motivo_alteracao = left(trim(p_motivo), 300)
   where id = p_id;
end;
$$;

create or replace function privado.cancelar_minha_visita(p_id bigint, p_motivo text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_ag public.visitas_agenda;
begin
  if not privado.acesso_ok() or privado.papel_atual() is distinct from 'analista' then perform privado.negar(); end if;
  select * into v_ag from public.visitas_agenda where id = p_id for update;
  if v_ag.id is null or v_ag.analista_id is distinct from auth.uid() then perform privado.invalido('visita não encontrada'); end if;
  if v_ag.criada_por is distinct from auth.uid() then
    perform privado.negar('visitas vinculadas pela gerência só são canceladas pela gerência');
  end if;
  if v_ag.status <> 'agendada' then perform privado.invalido('só visitas agendadas podem ser canceladas'); end if;
  if length(trim(coalesce(p_motivo, ''))) < 3 then perform privado.invalido('informe o motivo do cancelamento'); end if;
  update public.visitas_agenda
     set status = 'cancelada', cancelada_por = auth.uid(), cancelada_em = now(), motivo_alteracao = left(trim(p_motivo), 300)
   where id = p_id;
end;
$$;

create or replace function privado.presenca_analista(
  p_evento text, p_escola smallint, p_lat double precision, p_lng double precision,
  p_agenda bigint default null, p_obs text default null
)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_e public.escolas;
  v_p public.presencas_analista;
  v_ag public.visitas_agenda;
  v_dist integer;
  v_conf text;
  v_agora timestamptz := now();
begin
  if not privado.acesso_ok() or privado.papel_atual() is distinct from 'analista' then perform privado.negar(); end if;
  if p_evento not in ('inicio', 'fim') then perform privado.invalido('evento deve ser inicio ou fim'); end if;
  if (p_lat is null) <> (p_lng is null) or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    perform privado.invalido('localização inválida');
  end if;

  if p_evento = 'inicio' then
    select * into v_e from public.escolas where id = p_escola;
    if v_e.id is null or v_e.ativa is false then perform privado.invalido('escolha uma escola ativa'); end if;
    if not privado.ve_escola(p_escola) then perform privado.invalido('esta escola não é da sua carteira'); end if;
    if exists (select 1 from public.presencas_analista where analista_id = v_uid and fim is null) then
      perform privado.invalido('encerre a presença em andamento antes de iniciar outra');
    end if;
    if p_agenda is not null then
      select * into v_ag from public.visitas_agenda where id = p_agenda;
      if v_ag.id is null or v_ag.analista_id <> v_uid or v_ag.status <> 'agendada' or v_ag.escola_id <> p_escola then
        perform privado.invalido('visita da agenda inválida para esta escola');
      end if;
    end if;
  else
    select * into v_p from public.presencas_analista where analista_id = v_uid and fim is null for update;
    if v_p.id is null then perform privado.invalido('não há presença em andamento para encerrar'); end if;
    select * into v_e from public.escolas where id = v_p.escola_id;
  end if;

  if p_lat is null then
    v_conf := 'Sem localização';
  elsif v_e.latitude is null or v_e.longitude is null then
    v_conf := 'Escola sem localização';
  else
    v_dist := privado.distancia_m(p_lat, p_lng, v_e.latitude, v_e.longitude);
    if v_dist > v_e.raio_m then v_conf := 'Fora do raio'; end if;
  end if;

  if p_evento = 'fim' and v_p.data < privado.hoje() then
    update public.presencas_analista
       set fim = greatest(least(v_agora, ((v_p.data + 1)::timestamp at time zone 'America/Sao_Paulo') - interval '1 second'),
                          inicio + interval '1 second'),
           distancia_fim_m = null,
           conferencia = 'Encerrada em outro dia',
           observacao = coalesce(nullif(left(trim(coalesce(p_obs, '')), 300), ''), observacao)
     where id = v_p.id
    returning * into v_p;
  elsif p_evento = 'inicio' then
    insert into public.presencas_analista (analista_id, escola_id, data, inicio, distancia_inicio_m, conferencia, agenda_id, observacao)
    values (v_uid, p_escola, privado.hoje(), v_agora, v_dist, v_conf, p_agenda,
            nullif(left(trim(coalesce(p_obs, '')), 300), ''))
    returning * into v_p;
  else
    update public.presencas_analista
       set fim = greatest(v_agora, inicio + interval '1 second'), distancia_fim_m = v_dist,
           conferencia = coalesce(conferencia, v_conf),
           observacao = coalesce(nullif(left(trim(coalesce(p_obs, '')), 300), ''), observacao)
     where id = v_p.id
    returning * into v_p;
  end if;
  return jsonb_build_object('id', v_p.id, 'escola_id', v_p.escola_id, 'inicio', v_p.inicio, 'fim', v_p.fim,
                            'distancia_m', v_dist, 'conferencia', v_p.conferencia, 'agenda_id', v_p.agenda_id);
end;
$$;

create or replace function privado.dados_visita(p jsonb)
returns public.visitas
language plpgsql stable security definer set search_path = ''
as $$
declare v public.visitas; v_oc text;
begin
  v.escola_id := nullif(p ->> 'escola', '')::smallint;
  v.data := nullif(p ->> 'data', '')::date;
  v.tipo := p ->> 'tipo';
  v.subtipo := nullif(left(trim(coalesce(p ->> 'subtipo', '')), 80), '');
  v.participantes := nullif(left(trim(coalesce(p ->> 'participantes', '')), 500), '');
  v.solucao := nullif(left(trim(coalesce(p ->> 'solucao', '')), 80), '');
  v.observacao := nullif(left(trim(coalesce(p ->> 'observacao', '')), 2000), '');
  v.objetivo := nullif(p ->> 'objetivo', '');
  v.engajamento := nullif(p ->> 'engajamento', '')::smallint;
  v.boas_praticas := nullif(left(trim(coalesce(p ->> 'boas_praticas', '')), 1000), '');
  v.dificuldades := nullif(left(trim(coalesce(p ->> 'dificuldades', '')), 1000), '');
  v_oc := nullif(left(trim(coalesce(p ->> 'ocorrencias', '')), 200), '');
  v.ocorrencias := v_oc;
  v.ocorrencia_obs := case when v_oc is null then null else nullif(left(trim(coalesce(p ->> 'ocorrencia_obs', '')), 1000), '') end;
  if v.escola_id is null then perform privado.invalido('escolha a escola da visita'); end if;
  if not privado.ve_escola(v.escola_id) then perform privado.invalido('esta escola não é da sua carteira'); end if;
  if v.data is null or v.data > privado.hoje() then perform privado.invalido('a data da visita não pode ser futura'); end if;
  if coalesce(v.tipo, '') not in ('Suporte', 'Implantação', 'Acompanhamento', 'Formação') then
    perform privado.invalido('escolha o tipo de atendimento');
  end if;
  if length(coalesce(v.observacao, '')) < 10 then perform privado.invalido('descreva como foi a visita'); end if;
  if v.objetivo is not null and v.objetivo not in ('Sim', 'Parcialmente', 'Não') then perform privado.invalido('objetivo inválido'); end if;
  if v.engajamento is not null and v.engajamento not between 1 and 5 then perform privado.invalido('engajamento inválido'); end if;
  return v;
end;
$$;

create or replace function privado.registrar_visita(p jsonb)
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare
  v public.visitas;
  v_ag public.visitas_agenda;
  v_pr public.presencas_analista;
  v_id bigint;
begin
  if not privado.acesso_ok() or privado.papel_atual() is distinct from 'analista' then perform privado.negar(); end if;
  if jsonb_typeof(p) is distinct from 'object' then perform privado.invalido('dados da visita inválidos'); end if;
  v := privado.dados_visita(p);
  if v.data < privado.hoje() - 30 then perform privado.invalido('registre visitas dos últimos 30 dias'); end if;
  if nullif(p ->> 'agenda_id', '') is not null then
    select * into v_ag from public.visitas_agenda where id = (p ->> 'agenda_id')::bigint for update;
    if v_ag.id is null or v_ag.analista_id <> auth.uid() or v_ag.status <> 'agendada' or v_ag.escola_id <> v.escola_id then
      perform privado.invalido('a visita da agenda não confere com a escola');
    end if;
  else
    select * into v_ag from public.visitas_agenda
     where analista_id = auth.uid() and escola_id = v.escola_id and data = v.data and status = 'agendada'
     order by hora nulls last, id limit 1 for update;
  end if;
  if nullif(p ->> 'presenca_id', '') is not null then
    select * into v_pr from public.presencas_analista where id = (p ->> 'presenca_id')::bigint;
    if v_pr.id is null or v_pr.analista_id <> auth.uid() or v_pr.escola_id <> v.escola_id or v_pr.data <> v.data then
      perform privado.invalido('a presença informada não confere com a visita');
    end if;
    if exists (select 1 from public.visitas where presenca_id = v_pr.id) then
      perform privado.invalido('esta presença já tem visita registrada');
    end if;
  end if;
  insert into public.visitas (analista_id, escola_id, data, tipo, subtipo, participantes, solucao, observacao,
                              objetivo, engajamento, boas_praticas, dificuldades, ocorrencias, ocorrencia_obs, agenda_id, presenca_id)
  values (auth.uid(), v.escola_id, v.data, v.tipo, v.subtipo, v.participantes, v.solucao, v.observacao,
          v.objetivo, v.engajamento, v.boas_praticas, v.dificuldades, v.ocorrencias, v.ocorrencia_obs, v_ag.id, v_pr.id)
  returning id into v_id;
  if v_ag.id is not null then
    update public.visitas_agenda set status = 'realizada', visita_id = v_id where id = v_ag.id;
  end if;
  return v_id;
end;
$$;

create or replace function privado.editar_visita(p_id bigint, p jsonb)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_old public.visitas; v public.visitas;
begin
  if not privado.acesso_ok() or privado.papel_atual() is distinct from 'analista' then perform privado.negar(); end if;
  select * into v_old from public.visitas where id = p_id for update;
  if v_old.id is null or v_old.analista_id <> auth.uid() then perform privado.invalido('visita não encontrada'); end if;
  if v_old.data < privado.hoje() - 7 then perform privado.invalido('a visita só pode ser corrigida até 7 dias depois'); end if;
  v := privado.dados_visita(p || jsonb_build_object('escola', v_old.escola_id));
  if v.data < privado.hoje() - 7 then perform privado.invalido('a nova data deve estar nos últimos 7 dias'); end if;
  insert into public.visitas_historico (visita_id, antes, por)
  values (p_id, to_jsonb(v_old) - 'id' - 'analista_id' - 'escola_id' - 'criado_em' - 'agenda_id' - 'presenca_id', auth.uid());
  update public.visitas
     set data = v.data, tipo = v.tipo, subtipo = v.subtipo, participantes = v.participantes, solucao = v.solucao,
         observacao = v.observacao, objetivo = v.objetivo, engajamento = v.engajamento, boas_praticas = v.boas_praticas,
         dificuldades = v.dificuldades, ocorrencias = v.ocorrencias, ocorrencia_obs = v.ocorrencia_obs, editado_em = now()
   where id = p_id;
end;
$$;

create or replace function privado.reabrir_onboarding(p_id bigint)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_i public.onboarding_itens;
begin
  select * into v_i from public.onboarding_itens where id = p_id for update;
  if not privado.ve_tudo() then
    if not privado.acesso_ok() or privado.papel_atual() is distinct from 'analista'
       or v_i.id is null or v_i.carteira_id is distinct from privado.carteira_atual()
       or v_i.baixa_por is distinct from auth.uid() then
      perform privado.negar();
    end if;
  end if;
  update public.onboarding_itens set status = 'pendente', baixa_data = null, baixa_forma = null, baixa_obs = null, baixa_por = null
   where id = p_id;
  if not found then perform privado.invalido('item não encontrado'); end if;
end;
$$;

create or replace function public.agendar_minha_visita(
  p_escola smallint, p_data date, p_hora time, p_origem text,
  p_tipo text default null, p_foco text default null, p_orientacao text default null
)
returns bigint language sql security invoker set search_path = ''
as $$ select privado.agendar_minha_visita(p_escola, p_data, p_hora, p_origem, p_tipo, p_foco, p_orientacao) $$;

create or replace function public.remarcar_visita_agenda(p_id bigint, p_data date, p_hora time, p_motivo text)
returns void language sql security invoker set search_path = ''
as $$ select privado.remarcar_visita_agenda(p_id, p_data, p_hora, p_motivo) $$;

create or replace function public.cancelar_minha_visita(p_id bigint, p_motivo text)
returns void language sql security invoker set search_path = ''
as $$ select privado.cancelar_minha_visita(p_id, p_motivo) $$;

create or replace function public.presenca_analista(
  p_evento text, p_escola smallint, p_lat double precision, p_lng double precision,
  p_agenda bigint default null, p_obs text default null
)
returns jsonb language sql security invoker set search_path = ''
as $$ select privado.presenca_analista(p_evento, p_escola, p_lat, p_lng, p_agenda, p_obs) $$;

create or replace function public.registrar_visita(p jsonb)
returns bigint language sql security invoker set search_path = ''
as $$ select privado.registrar_visita(p) $$;

create or replace function public.editar_visita(p_id bigint, p jsonb)
returns void language sql security invoker set search_path = ''
as $$ select privado.editar_visita(p_id, p) $$;

revoke all on function
  privado.dia_de_visita(date), privado.pode_mexer_agenda(public.visitas_agenda), privado.dados_visita(jsonb)
  from public, anon, authenticated;
revoke all on function
  privado.agendar_minha_visita(smallint, date, time, text, text, text, text),
  privado.remarcar_visita_agenda(bigint, date, time, text),
  privado.cancelar_minha_visita(bigint, text),
  privado.presenca_analista(text, smallint, double precision, double precision, bigint, text),
  privado.registrar_visita(jsonb), privado.editar_visita(bigint, jsonb),
  public.agendar_minha_visita(smallint, date, time, text, text, text, text),
  public.remarcar_visita_agenda(bigint, date, time, text),
  public.cancelar_minha_visita(bigint, text),
  public.presenca_analista(text, smallint, double precision, double precision, bigint, text),
  public.registrar_visita(jsonb), public.editar_visita(bigint, jsonb)
  from public, anon;
grant execute on function
  privado.agendar_minha_visita(smallint, date, time, text, text, text, text),
  privado.remarcar_visita_agenda(bigint, date, time, text),
  privado.cancelar_minha_visita(bigint, text),
  privado.presenca_analista(text, smallint, double precision, double precision, bigint, text),
  privado.registrar_visita(jsonb), privado.editar_visita(bigint, jsonb),
  public.agendar_minha_visita(smallint, date, time, text, text, text, text),
  public.remarcar_visita_agenda(bigint, date, time, text),
  public.cancelar_minha_visita(bigint, text),
  public.presenca_analista(text, smallint, double precision, double precision, bigint, text),
  public.registrar_visita(jsonb), public.editar_visita(bigint, jsonb)
  to authenticated;

revoke insert, update on public.visitas from authenticated;
