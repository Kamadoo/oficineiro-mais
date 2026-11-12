alter table public.presencas
  add column if not exists ponto boolean not null default false,
  add column if not exists falta_status text not null default 'dentro',
  add column if not exists falta_motivo text,
  add column if not exists falta_justificativa text,
  add column if not exists falta_horarios jsonb,
  add column if not exists falta_obs text,
  add column if not exists falta_decidido_por uuid references public.perfis(id),
  add column if not exists falta_decidido_em timestamptz,
  add column if not exists marcacoes_informadas text[];

alter table public.presencas drop constraint if exists presencas_falta_check;
alter table public.presencas add constraint presencas_falta_check
  check (falta_status in ('dentro', 'aguardando', 'conferido', 'nao')
         and length(falta_motivo) <= 120 and length(falta_justificativa) <= 1000 and length(falta_obs) <= 500
         and (marcacoes_informadas is null or marcacoes_informadas <@ array['pausa', 'retorno', 'fim']));

create table if not exists public.presenca_marcacoes (
  id                    bigint generated always as identity primary key,
  presenca_id           bigint not null references public.presencas(id) on delete cascade,
  oficineiro_id         uuid not null references public.perfis(id),
  tipo                  text not null check (tipo in ('entrada', 'saida_almoco', 'retorno_almoco', 'saida')),
  registrado_em         timestamptz not null,
  recebido_em           timestamptz not null default now(),
  sem_internet          boolean not null default false,
  diferenca_relogio_s   integer,
  precisao_m            integer check (precisao_m between 0 and 100000),
  distancia_m           integer check (distancia_m >= 0),
  dentro_raio           boolean,
  escola_informada_id   smallint references public.escolas(id),
  distancia_informada_m integer check (distancia_informada_m >= 0),
  atividade_externa     boolean not null default false,
  justificativa         text check (length(justificativa) <= 1000),
  aparelho              text check (aparelho ~ '^[A-Za-z0-9-]{8,64}$'),
  unique (presenca_id, tipo)
);
create index if not exists presenca_marcacoes_oficineiro_idx on public.presenca_marcacoes (oficineiro_id, registrado_em);
alter table public.presenca_marcacoes enable row level security;
revoke all on public.presenca_marcacoes from anon, authenticated;
grant select on public.presenca_marcacoes to authenticated;
drop policy if exists presenca_marcacoes_ler on public.presenca_marcacoes;
create policy presenca_marcacoes_ler on public.presenca_marcacoes for select to authenticated
  using (exists (select 1 from public.presencas p where p.id = presenca_id));
drop trigger if exists auditoria on public.presenca_marcacoes;
create trigger auditoria after insert or update or delete on public.presenca_marcacoes
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
    select coalesce(sum(d.deficit_min), 0) into v_disp
      from public.presencas d
     where d.oficineiro_id = v_p.oficineiro_id and d.compensar_em = v_p.data and d.id <> v_p.id
       and d.deficit_status in ('aguardando', 'autorizado');
    v_comp := least(v_dif, v_disp);
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
                                 else 'pendente' end,
         deficit_min = v_def,
         deficit_status = case when v_def = 0 then 'dentro'
                               when deficit_status in ('aguardando', 'autorizado', 'nao') and deficit_min = v_def then deficit_status
                               else 'pendente' end
   where id = v_p.id;
end;
$$;

create or replace function privado.registrar_marcacao(p_evento text, p_lat double precision, p_lng double precision,
                                                      p_quando timestamptz default null, p_relogio timestamptz default null,
                                                      p_precisao integer default null, p_escola smallint default null,
                                                      p_externa boolean default false, p_justificativa text default null,
                                                      p_aparelho text default null)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_esc public.escolas;
  v_inf public.escolas;
  v_quando timestamptz := now();
  v_dif integer;
  v_conf text;
  v_dist integer;
  v_dist_inf integer;
  v_fora boolean := false;
  v_data date;
  v_p public.presencas;
  v_entrou boolean;
  v_tipo text;
  v_rotulo text;
  v_just text := nullif(left(trim(coalesce(p_justificativa, '')), 1000), '');
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  if p_evento not in ('inicio', 'fim', 'pausa', 'retorno') then perform privado.invalido('evento deve ser inicio, pausa, retorno ou fim'); end if;
  if (p_lat is null) <> (p_lng is null) or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    perform privado.invalido('localização inválida');
  end if;
  if p_aparelho is not null and p_aparelho !~ '^[A-Za-z0-9-]{8,64}$' then perform privado.invalido('identificação do aparelho inválida'); end if;
  if p_relogio is not null then
    v_dif := round(extract(epoch from (p_relogio - now())))::integer;
  end if;
  if p_quando is not null then
    v_quando := p_quando - make_interval(secs => coalesce(v_dif, 0));
    if v_quando > now() + interval '2 minutes' or v_quando < now() - interval '24 hours' then
      perform privado.invalido('horário guardado sem internet fora do limite de 24 horas');
    end if;
    v_conf := 'Enviado sem internet';
  end if;

  select * into v_esc from public.escolas where id = privado.escola_atual();
  if p_lat is null then
    v_conf := coalesce(v_conf, 'Sem localização');
  elsif v_esc.latitude is null or v_esc.longitude is null then
    v_conf := coalesce(v_conf, 'Escola sem localização');
  else
    v_dist := privado.distancia_m(p_lat, p_lng, v_esc.latitude, v_esc.longitude);
    v_fora := v_dist > v_esc.raio_m;
    if v_fora then v_conf := coalesce(v_conf, 'Fora do raio'); end if;
  end if;
  if p_escola is not null then
    select * into v_inf from public.escolas where id = p_escola;
    if v_inf.id is null then perform privado.invalido('escola informada não encontrada'); end if;
    if p_lat is not null and v_inf.latitude is not null and v_inf.longitude is not null then
      v_dist_inf := privado.distancia_m(p_lat, p_lng, v_inf.latitude, v_inf.longitude);
    end if;
  end if;
  v_data := (v_quando at time zone 'America/Sao_Paulo')::date;

  if p_evento = 'inicio' then
    insert into public.presencas (oficineiro_id, escola_id, data, inicio, distancia_inicio_m, conferencia, horario_status, ponto)
    values (v_uid, v_esc.id, v_data, v_quando, v_dist, v_conf, 'dentro', true)
    on conflict (oficineiro_id, data) do nothing
    returning * into v_p;
    if v_p.id is null then perform privado.invalido('a presença deste dia já foi iniciada'); end if;
  else
    select * into v_p from public.presencas
     where oficineiro_id = v_uid and data = v_data and fim is null for update;
    if p_evento = 'pausa' then
      if v_p.id is null then perform privado.invalido('não há presença iniciada hoje para pausar'); end if;
      if v_p.pausa_inicio is not null then perform privado.invalido('a saída para almoço deste dia já foi registrada'); end if;
      if v_quando <= v_p.inicio then perform privado.invalido('saída para almoço antes da entrada'); end if;
      update public.presencas set pausa_inicio = v_quando where id = v_p.id returning * into v_p;
    elsif p_evento = 'retorno' then
      if v_p.id is null then perform privado.invalido('não há presença iniciada hoje'); end if;
      if v_p.pausa_inicio is null or v_p.pausa_fim is not null then perform privado.invalido('não há saída para almoço em andamento'); end if;
      if v_quando < v_p.pausa_inicio then perform privado.invalido('retorno antes da saída para almoço'); end if;
      update public.presencas set pausa_fim = v_quando where id = v_p.id returning * into v_p;
    else
      if v_p.id is null then perform privado.invalido('não há presença iniciada hoje para encerrar'); end if;
      if v_p.ponto and v_p.pausa_inicio is null then perform privado.invalido('registre a saída e o retorno do almoço antes da saída'); end if;
      if v_p.ponto and v_p.pausa_fim is null then perform privado.invalido('registre o retorno do almoço antes da saída'); end if;
      if v_quando <= v_p.inicio then perform privado.invalido('encerramento antes do início'); end if;
      if v_p.pausa_inicio is not null and v_quando < v_p.pausa_inicio then perform privado.invalido('encerramento antes da pausa'); end if;
      if v_p.pausa_fim is not null and v_quando < v_p.pausa_fim then perform privado.invalido('saída antes do retorno do almoço'); end if;
      v_entrou := v_p.entrou_raio_em is null and v_dist is not null and v_dist <= v_esc.raio_m
                  and v_p.distancia_inicio_m is not null and v_p.distancia_inicio_m > v_esc.raio_m;
      update public.presencas
         set fim = v_quando,
             pausa_fim = case when pausa_inicio is not null and pausa_fim is null then v_quando else pausa_fim end,
             distancia_fim_m = v_dist,
             entrou_raio_em = case when v_entrou then v_quando else entrou_raio_em end,
             distancia_entrada_m = case when v_entrou then v_dist else distancia_entrada_m end
       where id = v_p.id
      returning * into v_p;
    end if;
    if v_conf is not null and v_p.conferencia is null then
      update public.presencas set conferencia = v_conf where id = v_p.id returning * into v_p;
    end if;
  end if;

  v_tipo := case p_evento when 'inicio' then 'entrada' when 'pausa' then 'saida_almoco' when 'retorno' then 'retorno_almoco' else 'saida' end;
  v_rotulo := case p_evento when 'inicio' then 'Entrada' when 'pausa' then 'Saída almoço' when 'retorno' then 'Retorno almoço' else 'Saída' end;
  insert into public.presenca_marcacoes (presenca_id, oficineiro_id, tipo, registrado_em, sem_internet, diferenca_relogio_s,
                                         precisao_m, distancia_m, dentro_raio, escola_informada_id, distancia_informada_m,
                                         atividade_externa, justificativa, aparelho)
  values (v_p.id, v_uid, v_tipo, v_quando, p_quando is not null, v_dif,
          case when p_precisao between 0 and 100000 then p_precisao end, v_dist,
          case when v_dist is null then null else not v_fora end, p_escola, v_dist_inf,
          coalesce(p_externa, false), v_just, p_aparelho)
  on conflict (presenca_id, tipo) do update
     set registrado_em = excluded.registrado_em, recebido_em = now(), sem_internet = excluded.sem_internet,
         diferenca_relogio_s = excluded.diferenca_relogio_s, precisao_m = excluded.precisao_m,
         distancia_m = excluded.distancia_m, dentro_raio = excluded.dentro_raio,
         escola_informada_id = excluded.escola_informada_id, distancia_informada_m = excluded.distancia_informada_m,
         atividade_externa = excluded.atividade_externa, justificativa = excluded.justificativa, aparelho = excluded.aparelho;

  if v_just is not null and (v_fora or p_escola is not null or coalesce(p_externa, false)) then
    update public.presencas
       set motivo = coalesce(motivo, conferencia),
           justificativa = left(coalesce(justificativa || ' · ', '') || v_rotulo ||
                                case when coalesce(p_externa, false) then ' (atividade externa)'
                                     when v_inf.id is not null then ' (' || v_inf.sigla || ')' else '' end ||
                                ': ' || v_just, 1000)
     where id = v_p.id
    returning * into v_p;
  end if;

  if p_evento = 'fim' then
    perform privado.calcular_dia(v_p.id);
    select * into v_p from public.presencas where id = v_p.id;
  end if;

  return jsonb_build_object('id', v_p.id, 'marcacao', v_tipo, 'distancia_m', v_dist, 'conferencia', v_p.conferencia,
                            'excedente_min', v_p.excedente_min, 'excedente_status', v_p.excedente_status,
                            'entrou_raio_em', v_p.entrou_raio_em, 'atraso_min', v_p.atraso_min, 'horario_status', v_p.horario_status,
                            'trabalhado_min', v_p.trabalhado_min, 'deficit_min', v_p.deficit_min, 'deficit_status', v_p.deficit_status,
                            'compensacao_min', v_p.compensacao_min, 'pausa_inicio', v_p.pausa_inicio, 'pausa_fim', v_p.pausa_fim,
                            'diferenca_relogio_s', v_dif);
end;
$$;

create or replace function privado.registrar_presenca(p_evento text, p_lat double precision, p_lng double precision, p_quando timestamptz default null)
returns jsonb
language sql security definer set search_path = ''
as $$
  select privado.registrar_marcacao(p_evento, p_lat, p_lng, p_quando);
$$;

create or replace function privado.justificar_marcacao(p_id bigint, p_motivo text, p_horarios jsonb, p_justificativa text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_p public.presencas;
  v_faltam text[];
  v_chave text;
  v_hora text;
  v_pausa timestamptz;
  v_retorno timestamptz;
  v_fim timestamptz;
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  select * into v_p from public.presencas where id = p_id and oficineiro_id = auth.uid() for update;
  if v_p.id is null then perform privado.negar(); end if;
  if not v_p.ponto then perform privado.invalido('este dia não usa as quatro marcações'); end if;
  if v_p.data >= privado.hoje() then perform privado.invalido('as marcações de hoje ainda podem ser feitas normalmente'); end if;
  if v_p.falta_status <> 'dentro' then perform privado.invalido('este dia já tem uma justificativa enviada'); end if;
  if not privado.mes_editavel(v_p.oficineiro_id, v_p.data) then perform privado.invalido('mês fechado: peça a devolução do relatório'); end if;
  v_faltam := array_remove(array[case when v_p.pausa_inicio is null then 'pausa' end,
                                 case when v_p.pausa_fim is null then 'retorno' end,
                                 case when v_p.fim is null then 'fim' end], null);
  if cardinality(v_faltam) = 0 then perform privado.invalido('este dia não tem marcação esquecida'); end if;
  if p_motivo is null or p_motivo not in ('Esqueci de marcar', 'Celular sem bateria', 'Sem internet / GPS não respondeu', 'Atividade externa', 'Outro') then
    perform privado.invalido('escolha o motivo');
  end if;
  if length(trim(coalesce(p_justificativa, ''))) < 10 then perform privado.invalido('descreva o que aconteceu em pelo menos 10 caracteres'); end if;
  if p_horarios is null or jsonb_typeof(p_horarios) <> 'object'
     or (select array_agg(k order by k) from jsonb_object_keys(p_horarios) k) is distinct from (select array_agg(x order by x) from unnest(v_faltam) x) then
    perform privado.invalido('informe o horário aproximado de cada marcação esquecida');
  end if;
  foreach v_chave in array v_faltam loop
    v_hora := p_horarios ->> v_chave;
    if v_hora is null or v_hora !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then perform privado.invalido('horário aproximado inválido'); end if;
  end loop;
  v_pausa := coalesce(v_p.pausa_inicio, ((v_p.data + (p_horarios ->> 'pausa')::time) at time zone 'America/Sao_Paulo'));
  v_retorno := coalesce(v_p.pausa_fim, ((v_p.data + (p_horarios ->> 'retorno')::time) at time zone 'America/Sao_Paulo'));
  v_fim := coalesce(v_p.fim, ((v_p.data + (p_horarios ->> 'fim')::time) at time zone 'America/Sao_Paulo'));
  if not (v_p.inicio < v_pausa and v_pausa <= v_retorno and v_retorno < v_fim) then
    perform privado.invalido('os horários precisam seguir a ordem entrada, saída para almoço, retorno e saída');
  end if;
  update public.presencas
     set falta_status = 'aguardando',
         falta_motivo = p_motivo,
         falta_justificativa = left(trim(p_justificativa), 1000),
         falta_horarios = p_horarios,
         falta_obs = null, falta_decidido_por = null, falta_decidido_em = null
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
  if privado.papel_atual() is distinct from 'coordenador' or not privado.acesso_ok() then perform privado.negar(); end if;
  select * into v_p from public.presencas where id = p_id for update;
  if v_p.id is null then perform privado.invalido('presença não encontrada'); end if;
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
  if privado.papel_atual() is distinct from 'coordenador' or not privado.acesso_ok() then perform privado.negar(); end if;
  select * into v_p from public.presencas where id = p_id for update;
  if v_p.id is null then perform privado.invalido('presença não encontrada'); end if;
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

revoke all on function privado.registrar_marcacao(text, double precision, double precision, timestamptz, timestamptz, integer, smallint, boolean, text, text),
  privado.justificar_marcacao(bigint, text, jsonb, text), privado.decidir_marcacao(bigint, boolean, text) from public, anon;
grant execute on function privado.registrar_marcacao(text, double precision, double precision, timestamptz, timestamptz, integer, smallint, boolean, text, text),
  privado.justificar_marcacao(bigint, text, jsonb, text), privado.decidir_marcacao(bigint, boolean, text) to authenticated;

create or replace function public.registrar_marcacao(p_evento text, p_lat double precision, p_lng double precision,
                                                     p_quando timestamptz default null, p_relogio timestamptz default null,
                                                     p_precisao integer default null, p_escola smallint default null,
                                                     p_externa boolean default false, p_justificativa text default null,
                                                     p_aparelho text default null)
returns jsonb language sql security invoker set search_path = ''
as $$ select privado.registrar_marcacao(p_evento, p_lat, p_lng, p_quando, p_relogio, p_precisao, p_escola, p_externa, p_justificativa, p_aparelho) $$;

create or replace function public.justificar_marcacao(p_id bigint, p_motivo text, p_horarios jsonb, p_justificativa text)
returns void language sql security invoker set search_path = ''
as $$ select privado.justificar_marcacao(p_id, p_motivo, p_horarios, p_justificativa) $$;

create or replace function public.decidir_marcacao(p_id bigint, p_aceitar boolean, p_comentario text default null)
returns void language sql security invoker set search_path = ''
as $$ select privado.decidir_marcacao(p_id, p_aceitar, p_comentario) $$;

revoke all on function public.registrar_marcacao(text, double precision, double precision, timestamptz, timestamptz, integer, smallint, boolean, text, text),
  public.justificar_marcacao(bigint, text, jsonb, text), public.decidir_marcacao(bigint, boolean, text) from public, anon;
grant execute on function public.registrar_marcacao(text, double precision, double precision, timestamptz, timestamptz, integer, smallint, boolean, text, text),
  public.justificar_marcacao(bigint, text, jsonb, text), public.decidir_marcacao(bigint, boolean, text) to authenticated;
