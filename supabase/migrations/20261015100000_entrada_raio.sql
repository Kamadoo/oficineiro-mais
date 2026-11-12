alter table public.presencas
  add column if not exists entrou_raio_em      timestamptz,
  add column if not exists distancia_entrada_m integer check (distancia_entrada_m >= 0);

create or replace function privado.registrar_presenca(
  p_evento     text,
  p_lat        double precision,
  p_lng        double precision,
  p_quando     timestamptz default null
)
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
  v_min integer;
  v_entrou boolean;
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  if p_evento not in ('inicio', 'fim') then perform privado.invalido('evento deve ser inicio ou fim'); end if;
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
    insert into public.presencas (oficineiro_id, escola_id, data, inicio, distancia_inicio_m, conferencia)
    values (v_uid, v_esc.id, v_data, v_quando, v_dist, v_conf)
    on conflict (oficineiro_id, data) do nothing
    returning * into v_p;
    if v_p.id is null then perform privado.invalido('a presença deste dia já foi iniciada'); end if;
  else
    select * into v_p from public.presencas
     where oficineiro_id = v_uid and data = v_data and fim is null for update;
    if v_p.id is null then perform privado.invalido('não há presença iniciada hoje para encerrar'); end if;
    if v_quando <= v_p.inicio then perform privado.invalido('encerramento antes do início'); end if;
    v_min := floor(extract(epoch from (v_quando - v_p.inicio)) / 60);
    v_entrou := v_p.entrou_raio_em is null and v_dist is not null and v_dist <= v_esc.raio_m
                and v_p.distancia_inicio_m is not null and v_p.distancia_inicio_m > v_esc.raio_m;
    update public.presencas
       set fim = v_quando,
           distancia_fim_m = v_dist,
           conferencia = coalesce(conferencia, v_conf),
           excedente_min = greatest(0, v_min - 480),
           excedente_status = case when v_min > 480 then 'pendente' else 'dentro' end,
           entrou_raio_em = case when v_entrou then v_quando else entrou_raio_em end,
           distancia_entrada_m = case when v_entrou then v_dist else distancia_entrada_m end
     where id = v_p.id
     returning * into v_p;
  end if;

  return jsonb_build_object('id', v_p.id, 'distancia_m', v_dist, 'conferencia', v_p.conferencia,
                            'excedente_min', v_p.excedente_min, 'excedente_status', v_p.excedente_status,
                            'entrou_raio_em', v_p.entrou_raio_em);
end;
$$;
revoke all on function privado.registrar_presenca(text, double precision, double precision, timestamptz) from public, anon;
grant execute on function privado.registrar_presenca(text, double precision, double precision, timestamptz) to authenticated;

create or replace function privado.registrar_entrada_raio(p_lat double precision, p_lng double precision, p_quando timestamptz default null)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_esc public.escolas;
  v_quando timestamptz := now();
  v_dist integer;
  v_p public.presencas;
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    perform privado.invalido('localização inválida');
  end if;
  if p_quando is not null then
    if p_quando > now() + interval '2 minutes' or p_quando < now() - interval '24 hours' then
      perform privado.invalido('horário guardado sem internet fora do limite de 24 horas');
    end if;
    v_quando := p_quando;
  end if;
  select * into v_p from public.presencas
   where oficineiro_id = auth.uid() and data = (v_quando at time zone 'America/Sao_Paulo')::date for update;
  if v_p.id is null or v_quando < v_p.inicio or (v_p.fim is not null and v_quando >= v_p.fim) then
    perform privado.invalido('não há atividades em andamento neste horário');
  end if;
  select * into v_esc from public.escolas where id = v_p.escola_id;
  if v_esc.latitude is null or v_esc.longitude is null or v_p.distancia_inicio_m is null or v_p.distancia_inicio_m <= v_esc.raio_m then
    perform privado.invalido('as atividades deste dia não começaram fora do raio');
  end if;
  if v_p.entrou_raio_em is not null then
    return jsonb_build_object('id', v_p.id, 'entrou_raio_em', v_p.entrou_raio_em);
  end if;
  v_dist := privado.distancia_m(p_lat, p_lng, v_esc.latitude, v_esc.longitude);
  if v_dist > v_esc.raio_m then perform privado.invalido('a localização ainda está fora do raio da escola'); end if;
  update public.presencas set entrou_raio_em = v_quando, distancia_entrada_m = v_dist
   where id = v_p.id
   returning * into v_p;
  return jsonb_build_object('id', v_p.id, 'entrou_raio_em', v_p.entrou_raio_em);
end;
$$;

create or replace function public.registrar_entrada_raio(p_lat double precision, p_lng double precision, p_quando timestamptz default null)
returns jsonb language sql security invoker set search_path = ''
as $$ select privado.registrar_entrada_raio(p_lat, p_lng, p_quando) $$;

revoke all on function privado.registrar_entrada_raio(double precision, double precision, timestamptz),
                       public.registrar_entrada_raio(double precision, double precision, timestamptz) from public, anon;
grant execute on function privado.registrar_entrada_raio(double precision, double precision, timestamptz),
                          public.registrar_entrada_raio(double precision, double precision, timestamptz) to authenticated;
