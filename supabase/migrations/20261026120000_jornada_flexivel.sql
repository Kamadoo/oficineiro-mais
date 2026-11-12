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
