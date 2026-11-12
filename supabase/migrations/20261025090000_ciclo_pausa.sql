create or replace function privado.ciclo_de(p_data date)
returns date
language sql immutable set search_path = ''
as $$
  select case when extract(day from p_data) >= 21
              then (date_trunc('month', p_data) + interval '1 month')::date
              else date_trunc('month', p_data)::date end;
$$;

create or replace function privado.ciclo_inicio(p_competencia date)
returns date
language sql immutable set search_path = ''
as $$
  select (date_trunc('month', p_competencia) - interval '1 month' + interval '20 days')::date;
$$;

create or replace function privado.ciclo_fim(p_competencia date)
returns date
language sql immutable set search_path = ''
as $$
  select (date_trunc('month', p_competencia) + interval '19 days')::date;
$$;

revoke all on function privado.ciclo_de(date), privado.ciclo_inicio(date), privado.ciclo_fim(date) from public, anon;
grant execute on function privado.ciclo_de(date), privado.ciclo_inicio(date), privado.ciclo_fim(date) to authenticated;

alter table public.presencas
  add column if not exists pausa_inicio timestamptz,
  add column if not exists pausa_fim timestamptz;

alter table public.presencas drop constraint if exists presencas_pausa_check;
alter table public.presencas add constraint presencas_pausa_check
  check ((pausa_fim is null or pausa_inicio is not null) and (pausa_fim is null or pausa_fim >= pausa_inicio));

create or replace function privado.minutos_trabalhados(p_inicio timestamptz, p_fim timestamptz, p_pausa_inicio timestamptz, p_pausa_fim timestamptz)
returns integer
language sql immutable set search_path = ''
as $$
  select case
           when p_pausa_inicio is null then privado.minutos_trabalhados(p_inicio, p_fim)
           else greatest(0,
                  floor(extract(epoch from (p_fim - p_inicio)) / 60)::int
                  - greatest(0, floor(extract(epoch from (least(p_fim, coalesce(p_pausa_fim, p_fim)) - greatest(p_inicio, p_pausa_inicio))) / 60)::int))
         end
$$;

revoke all on function privado.minutos_trabalhados(timestamptz, timestamptz, timestamptz, timestamptz) from public, anon, authenticated;

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
  v_trab := privado.minutos_trabalhados(v_p.inicio, v_p.fim, v_p.pausa_inicio, v_p.pausa_fim);
  v_prev := privado.minutos_previstos(v_p.data);
  v_dif := v_trab - v_prev;
  if v_dif > 15 then
    select coalesce(sum(d.deficit_min), 0) into v_disp
      from public.presencas d
     where d.oficineiro_id = v_p.oficineiro_id and d.compensar_em = v_p.data and d.id <> v_p.id
       and d.deficit_status in ('aguardando', 'autorizado');
    v_comp := least(v_dif, v_disp);
    v_exc := v_dif - v_comp;
    if v_exc <= 15 then v_exc := 0; end if;
  elsif v_dif < -15 then
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

update public.perfis set jornada_inicio = '07:00' where papel = 'oficineiro' and jornada_inicio is distinct from '07:00';

create or replace function privado.definir_jornada(p_usuario uuid, p_inicio time)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not coalesce(privado.gestor_ok(), false) then perform privado.negar(); end if;
  if p_inicio is null or p_inicio <> '07:00' then perform privado.invalido('o horário de trabalho dos oficineiros começa às 07:00'); end if;
  update public.perfis set jornada_inicio = p_inicio where id = p_usuario and papel = 'oficineiro';
  if not found then perform privado.invalido('o horário de trabalho só vale para contas de oficineiro'); end if;
end;
$$;

create or replace function privado.registrar_presenca(p_evento text, p_lat double precision, p_lng double precision, p_quando timestamptz default null)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_esc public.escolas;
  v_quando timestamptz := now();
  v_conf text;
  v_dist integer;
  v_data date;
  v_p public.presencas;
  v_entrou boolean;
  v_jor time;
  v_atraso integer;
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  if p_evento not in ('inicio', 'fim', 'pausa', 'retorno') then perform privado.invalido('evento deve ser inicio, pausa, retorno ou fim'); end if;
  if (p_lat is null) <> (p_lng is null) or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    perform privado.invalido('localização inválida');
  end if;
  if p_quando is not null then
    if p_quando > now() + interval '2 minutes' or p_quando < now() - interval '24 hours' then
      perform privado.invalido('horário guardado sem internet fora do limite de 24 horas');
    end if;
    v_quando := p_quando;
    v_conf := 'Enviado sem internet';
  end if;

  select * into v_esc from public.escolas where id = privado.escola_atual();
  if p_lat is null then
    v_conf := coalesce(v_conf, 'Sem localização');
  elsif v_esc.latitude is null or v_esc.longitude is null then
    v_conf := coalesce(v_conf, 'Escola sem localização');
  else
    v_dist := privado.distancia_m(p_lat, p_lng, v_esc.latitude, v_esc.longitude);
    if v_dist > v_esc.raio_m then v_conf := coalesce(v_conf, 'Fora do raio'); end if;
  end if;
  v_data := (v_quando at time zone 'America/Sao_Paulo')::date;

  if p_evento = 'inicio' then
    select coalesce(jornada_inicio, '07:00') into v_jor from public.perfis where id = v_uid;
    if v_jor is not null and privado.minutos_previstos(v_data) > 0 then
      v_atraso := (extract(epoch from ((v_quando at time zone 'America/Sao_Paulo')::time - v_jor)) / 60)::int;
    end if;
    insert into public.presencas (oficineiro_id, escola_id, data, inicio, distancia_inicio_m, conferencia, atraso_min, horario_status)
    values (v_uid, v_esc.id, v_data, v_quando, v_dist, v_conf, v_atraso, privado.situacao_horario(v_atraso))
    on conflict (oficineiro_id, data) do nothing
    returning * into v_p;
    if v_p.id is null then perform privado.invalido('a presença deste dia já foi iniciada'); end if;
  elsif p_evento = 'pausa' then
    select * into v_p from public.presencas
     where oficineiro_id = v_uid and data = v_data and fim is null for update;
    if v_p.id is null then perform privado.invalido('não há presença iniciada hoje para pausar'); end if;
    if v_p.pausa_inicio is not null then perform privado.invalido('a pausa para almoço deste dia já foi registrada'); end if;
    if v_quando <= v_p.inicio then perform privado.invalido('pausa antes do início da presença'); end if;
    update public.presencas set pausa_inicio = v_quando where id = v_p.id returning * into v_p;
  elsif p_evento = 'retorno' then
    select * into v_p from public.presencas
     where oficineiro_id = v_uid and data = v_data and fim is null for update;
    if v_p.id is null then perform privado.invalido('não há presença iniciada hoje'); end if;
    if v_p.pausa_inicio is null or v_p.pausa_fim is not null then perform privado.invalido('não há pausa em andamento para retomar'); end if;
    if v_quando < v_p.pausa_inicio then perform privado.invalido('retorno antes do início da pausa'); end if;
    update public.presencas set pausa_fim = v_quando where id = v_p.id returning * into v_p;
  else
    select * into v_p from public.presencas
     where oficineiro_id = v_uid and data = v_data and fim is null for update;
    if v_p.id is null then perform privado.invalido('não há presença iniciada hoje para encerrar'); end if;
    if v_quando <= v_p.inicio then perform privado.invalido('encerramento antes do início'); end if;
    if v_p.pausa_inicio is not null and v_quando < v_p.pausa_inicio then perform privado.invalido('encerramento antes da pausa'); end if;
    v_entrou := v_p.entrou_raio_em is null and v_dist is not null and v_dist <= v_esc.raio_m
                and v_p.distancia_inicio_m is not null and v_p.distancia_inicio_m > v_esc.raio_m;
    update public.presencas
       set fim = v_quando,
           pausa_fim = case when pausa_inicio is not null and pausa_fim is null then v_quando else pausa_fim end,
           distancia_fim_m = v_dist,
           conferencia = coalesce(conferencia, v_conf),
           entrou_raio_em = case when v_entrou then v_quando else entrou_raio_em end,
           distancia_entrada_m = case when v_entrou then v_dist else distancia_entrada_m end
     where id = v_p.id;
    perform privado.calcular_dia(v_p.id);
    select * into v_p from public.presencas where id = v_p.id;
  end if;

  return jsonb_build_object('id', v_p.id, 'distancia_m', v_dist, 'conferencia', v_p.conferencia,
                            'excedente_min', v_p.excedente_min, 'excedente_status', v_p.excedente_status,
                            'entrou_raio_em', v_p.entrou_raio_em, 'atraso_min', v_p.atraso_min, 'horario_status', v_p.horario_status,
                            'trabalhado_min', v_p.trabalhado_min, 'deficit_min', v_p.deficit_min, 'deficit_status', v_p.deficit_status,
                            'compensacao_min', v_p.compensacao_min, 'pausa_inicio', v_p.pausa_inicio, 'pausa_fim', v_p.pausa_fim);
end;
$$;

create or replace function privado.reabrir_presenca(p_id bigint)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_p public.presencas;
  v_n integer;
  v_trab integer;
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  select * into v_p from public.presencas where id = p_id and oficineiro_id = auth.uid() for update;
  if v_p.id is null then perform privado.negar(); end if;
  if v_p.fim is null then perform privado.invalido('esta presença ainda não foi encerrada'); end if;
  if v_p.data <> privado.hoje() then perform privado.invalido('só é possível desfazer o encerramento no mesmo dia'); end if;
  if not privado.mes_editavel(v_p.oficineiro_id, v_p.data) then perform privado.invalido('ciclo fechado: peça a devolução do relatório'); end if;
  v_trab := coalesce(v_p.trabalhado_min, privado.minutos_trabalhados(v_p.inicio, v_p.fim, v_p.pausa_inicio, v_p.pausa_fim));
  if v_trab >= 480 then
    perform privado.invalido('o dia já tem 8 horas ou mais: o encerramento não pode ser desfeito');
  end if;
  select count(*) into v_n from public.presenca_reaberturas where presenca_id = v_p.id;
  if v_n >= 2 then perform privado.invalido('o encerramento deste dia já foi desfeito 2 vezes'); end if;
  insert into public.presenca_reaberturas (presenca_id, oficineiro_id, escola_id, data, inicio, fim_anterior, trabalhado_min)
  values (v_p.id, v_p.oficineiro_id, v_p.escola_id, v_p.data, v_p.inicio, v_p.fim, v_trab);
  update public.presencas
     set fim = null, distancia_fim_m = null, trabalhado_min = null, previsto_min = null,
         pausa_fim = case when pausa_fim = v_p.fim then null else pausa_fim end,
         compensacao_min = 0, excedente_min = 0, excedente_status = 'dentro',
         deficit_min = 0, deficit_status = 'dentro', motivo_deficit = null, justificativa_deficit = null, compensar_em = null
   where id = v_p.id;
  perform privado.recalcular_compensacao(v_p.oficineiro_id, v_p.compensar_em);
end;
$$;

create or replace function privado.registro_na_presenca()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_ini timestamptz;
  v_fim timestamptz;
  v_p public.presencas;
begin
  if auth.uid() is null or auth.uid() <> new.oficineiro_id then return null; end if;
  if new.situacao not in ('Realizada', 'Realizada parcialmente') then return null; end if;
  if tg_op = 'UPDATE' and old.situacao in ('Realizada', 'Realizada parcialmente')
     and old.data = new.data and old.inicio = new.inicio and old.fim = new.fim then
    return null;
  end if;
  v_ini := (new.data + new.inicio) at time zone 'America/Sao_Paulo';
  v_fim := (new.data + new.fim) at time zone 'America/Sao_Paulo';
  select * into v_p from public.presencas p
   where p.oficineiro_id = new.oficineiro_id and p.data = new.data
     and p.inicio <= v_ini and coalesce(p.fim, greatest(now(), v_fim)) >= v_fim;
  if v_p.id is null then
    perform privado.invalido('a atividade só pode ser registrada como realizada se você estava com a presença iniciada na escola nesse horário');
  end if;
  if v_p.pausa_inicio is not null and v_fim > v_p.pausa_inicio
     and v_ini < coalesce(v_p.pausa_fim, 'infinity'::timestamptz) then
    perform privado.invalido('a atividade não pode ser registrada dentro do intervalo da pausa para almoço');
  end if;
  return null;
end;
$$;

create or replace function privado.mes_editavel(p_oficineiro uuid, p_data date)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select p_data <= privado.hoje()
     and not exists (select 1 from public.relatorios_mensais r
                     where r.oficineiro_id = p_oficineiro
                       and r.competencia = privado.ciclo_de(p_data)
                       and r.status <> 'devolvido')
     and (privado.ciclo_de(p_data) = privado.ciclo_de(privado.hoje())
          or exists (select 1 from public.relatorios_mensais r
                     where r.oficineiro_id = p_oficineiro
                       and r.competencia = privado.ciclo_de(p_data)
                       and r.status = 'devolvido'));
$$;

create or replace function privado.fechar_relatorio(p_competencia date)
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare
  v_comp date := date_trunc('month', p_competencia)::date;
  v_id bigint;
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  if v_comp > privado.ciclo_de(privado.hoje()) then perform privado.invalido('não é possível fechar um ciclo futuro'); end if;
  if v_comp >= privado.ciclo_de(privado.hoje())
     and not exists (select 1 from public.relatorios_mensais r
                      where r.oficineiro_id = auth.uid() and r.competencia = v_comp and r.status = 'devolvido') then
    perform privado.invalido('o ciclo ainda não terminou: ele fecha sozinho depois do dia 20');
  end if;
  insert into public.relatorios_mensais (oficineiro_id, escola_id, competencia, status)
  values (auth.uid(), privado.escola_atual(), v_comp, 'fechado')
  on conflict (oficineiro_id, competencia) do update
     set status = 'fechado', fechado_em = now(), motivo_devolucao = null,
         direcao_por = null, direcao_em = null, coordenacao_por = null, coordenacao_em = null
   where public.relatorios_mensais.status = 'devolvido'
  returning id into v_id;
  if v_id is null then perform privado.invalido('este ciclo já está fechado'); end if;
  return v_id;
end;
$$;

create or replace function privado.enviar_lembrete(p_grade_aula_id bigint, p_data date)
returns timestamptz
language plpgsql security definer set search_path = ''
as $$
declare
  g public.grade_aulas;
  v_ult timestamptz;
begin
  if privado.papel_atual() is distinct from 'coordenador' or not privado.acesso_ok() or privado.eh_admin() then perform privado.negar(); end if;
  select * into g from public.grade_aulas where id = p_grade_aula_id;
  if g.id is null or not privado.ve_escola(g.escola_id) then perform privado.negar(); end if;
  if p_data is null or p_data > privado.hoje() then perform privado.invalido('a aula ainda não aconteceu'); end if;
  if privado.ciclo_de(p_data) <> privado.ciclo_de(privado.hoje()) then perform privado.invalido('o ciclo desta aula já terminou e ela não pode mais ser registrada'); end if;
  if g.ano_letivo <> extract(year from p_data) or g.dia_semana <> extract(isodow from p_data) then perform privado.invalido('esta aula não está na grade neste dia'); end if;
  if exists (select 1 from public.aulas_registro r where r.grade_aula_id = g.id and r.data = p_data) then perform privado.invalido('esta aula já foi registrada'); end if;
  select enviado_em into v_ult from public.lembretes_registro where grade_aula_id = g.id and data = p_data;
  if v_ult is not null and v_ult > now() - interval '20 hours' then perform privado.invalido('o lembrete desta aula já foi enviado hoje'); end if;
  insert into public.lembretes_registro as l (oficineiro_id, escola_id, grade_aula_id, data, enviado_por)
  values (g.oficineiro_id, g.escola_id, g.id, p_data, auth.uid())
  on conflict (grade_aula_id, data) do update set enviado_em = now(), enviado_por = auth.uid()
  returning l.enviado_em into v_ult;
  return v_ult;
end;
$$;

create or replace function privado.meus_lembretes()
returns table(id bigint, grade_aula_id bigint, data date, enviado_em timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  return query
    select l.id, l.grade_aula_id, l.data, l.enviado_em
      from public.lembretes_registro l
     where l.oficineiro_id = auth.uid()
       and privado.ciclo_de(l.data) = privado.ciclo_de(privado.hoje())
       and not exists (select 1 from public.aulas_registro r where r.grade_aula_id = l.grade_aula_id and r.data = l.data)
     order by l.data;
end;
$$;

create or replace function privado.admin_consulta(p_usuario uuid, p_competencia date)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_comp date := case when p_competencia is null then privado.ciclo_de(privado.hoje())
                      else date_trunc('month', p_competencia)::date end;
  v_ini date := privado.ciclo_inicio(v_comp);
  v_fim date := privado.ciclo_fim(v_comp) + 1;
  v_p public.perfis;
begin
  if not privado.eh_admin() then perform privado.negar(); end if;
  select * into v_p from public.perfis where id = p_usuario;
  if v_p.id is null then perform privado.invalido('conta não encontrada'); end if;
  return jsonb_build_object(
    'perfil', jsonb_build_object('id', v_p.id, 'nome', v_p.nome, 'usuario', v_p.usuario, 'papel', v_p.papel::text,
                                 'escola_id', v_p.escola_id, 'carteira_id', v_p.carteira_id, 'ativo', v_p.ativo,
                                 'jornada_inicio', to_char(v_p.jornada_inicio, 'HH24:MI')),
    'competencia', v_comp,
    'ciclo_inicio', v_ini,
    'ciclo_fim', v_fim - 1,
    'presencas', coalesce((select jsonb_agg(jsonb_build_object(
        'id', p.id, 'data', p.data, 'escola_id', p.escola_id, 'inicio', p.inicio, 'fim', p.fim,
        'pausa_inicio', p.pausa_inicio, 'pausa_fim', p.pausa_fim,
        'conferencia', p.conferencia, 'conferencia_status', p.conferencia_status,
        'trabalhado_min', p.trabalhado_min, 'previsto_min', p.previsto_min,
        'excedente_min', p.excedente_min, 'excedente_status', p.excedente_status,
        'deficit_min', p.deficit_min, 'deficit_status', p.deficit_status,
        'atraso_min', p.atraso_min, 'horario_status', p.horario_status,
        'compensacao_min', p.compensacao_min, 'compensar_em', p.compensar_em) order by p.data)
      from public.presencas p where p.oficineiro_id = v_p.id and p.data >= v_ini and p.data < v_fim), '[]'::jsonb),
    'registros', coalesce((select jsonb_agg(jsonb_build_object(
        'id', r.id, 'data', r.data, 'inicio', to_char(r.inicio, 'HH24:MI'), 'turma', r.turma, 'componente', r.componente,
        'oficina', r.oficina, 'tipo', r.tipo,
        'situacao', r.situacao, 'revisao_status', r.revisao_status, 'revisao_obs', r.revisao_obs) order by r.data, r.inicio)
      from public.aulas_registro r where r.oficineiro_id = v_p.id and r.data >= v_ini and r.data < v_fim), '[]'::jsonb),
    'relatorio', (select jsonb_build_object('id', m.id, 'status', m.status, 'motivo_devolucao', m.motivo_devolucao)
                    from public.relatorios_mensais m where m.oficineiro_id = v_p.id and m.competencia = v_comp),
    'grades', coalesce((select jsonb_agg(jsonb_build_object('ano_letivo', e.ano_letivo, 'status', e.status, 'comentario', e.comentario)
                                         order by e.ano_letivo)
                          from public.grade_envios e where e.oficineiro_id = v_p.id), '[]'::jsonb)
  );
end;
$$;

create or replace function privado.admin_reabrir_mes(p_oficineiro uuid, p_competencia date, p_motivo text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_of public.perfis;
  v_motivo text;
  v_comp date := date_trunc('month', p_competencia)::date;
  v_m public.relatorios_mensais;
begin
  if not privado.eh_admin() then perform privado.negar(); end if;
  v_motivo := privado.admin_motivo(p_motivo);
  select * into v_of from public.perfis where id = p_oficineiro;
  if v_of.id is null or v_of.papel::text <> 'oficineiro' then perform privado.invalido('escolha uma conta de oficineiro'); end if;
  if p_competencia is null or v_comp > privado.ciclo_de(privado.hoje()) then perform privado.invalido('escolha um ciclo que já começou'); end if;
  select * into v_m from public.relatorios_mensais where oficineiro_id = v_of.id and competencia = v_comp for update;
  if v_m.id is not null and v_m.status = 'devolvido' then perform privado.invalido('este ciclo já está aberto para correção'); end if;
  if v_m.id is null then
    if v_comp = privado.ciclo_de(privado.hoje()) then perform privado.invalido('o ciclo atual já está aberto'); end if;
    insert into public.relatorios_mensais (oficineiro_id, escola_id, competencia, status, motivo_devolucao)
    values (v_of.id, v_of.escola_id, v_comp, 'devolvido', v_motivo);
  else
    update public.relatorios_mensais set status = 'devolvido', motivo_devolucao = v_motivo where id = v_m.id;
  end if;
  perform privado.admin_correcao('relatorios_mensais', v_of.id::text, v_motivo,
    jsonb_build_object('competencia', v_comp, 'status', jsonb_build_object('de', coalesce(v_m.status, 'fechado'), 'para', 'devolvido')));
end;
$$;

create or replace function privado.garantir_relatorios(p_competencia date)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_comp date := date_trunc('month', p_competencia)::date;
  v_ini date := privado.ciclo_inicio(date_trunc('month', p_competencia)::date);
  v_fim date := privado.ciclo_fim(date_trunc('month', p_competencia)::date) + 1;
begin
  if v_comp >= privado.ciclo_de(privado.hoje()) then return; end if;
  insert into public.relatorios_mensais (oficineiro_id, escola_id, competencia, status, fechado_em)
  select p.id, p.escola_id, v_comp, 'fechado', (v_fim::timestamp at time zone 'America/Sao_Paulo')
    from public.perfis p
   where p.papel::text = 'oficineiro'
     and p.escola_id is not null
     and privado.ve_escola(p.escola_id)
     and (exists (select 1 from public.presencas x where x.oficineiro_id = p.id and x.data >= v_ini and x.data < v_fim)
          or exists (select 1 from public.aulas_registro x where x.oficineiro_id = p.id and x.data >= v_ini and x.data < v_fim)
          or exists (select 1 from public.grade_aulas g
                      where g.oficineiro_id = p.id
                        and g.ano_letivo between extract(year from v_ini) and extract(year from v_fim - 1)
                        and g.criado_em < (v_fim::timestamp at time zone 'America/Sao_Paulo')))
  on conflict (oficineiro_id, competencia) do nothing;
end;
$$;

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
   where r.competencia = v_comp
     and privado.ve_escola(r.escola_id)
   order by e.sigla, o.nome;
end;
$$;
