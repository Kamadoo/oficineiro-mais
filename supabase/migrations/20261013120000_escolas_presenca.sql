alter table public.escolas add column if not exists telefone text check (length(telefone) <= 20);
alter table public.escolas add column if not exists posicao_confirmada boolean not null default false;

alter table public.presencas drop constraint if exists presencas_conferencia_check;
alter table public.presencas add constraint presencas_conferencia_check
  check (conferencia in ('Fora do raio', 'Sem encerramento', 'Enviado sem internet', 'Sem localização', 'Escola sem localização'));

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
    update public.presencas
       set fim = v_quando,
           distancia_fim_m = v_dist,
           conferencia = coalesce(conferencia, v_conf),
           excedente_min = greatest(0, v_min - 480),
           excedente_status = case when v_min > 480 then 'pendente' else 'dentro' end
     where id = v_p.id
     returning * into v_p;
  end if;

  return jsonb_build_object('id', v_p.id, 'distancia_m', v_dist, 'conferencia', v_p.conferencia,
                            'excedente_min', v_p.excedente_min, 'excedente_status', v_p.excedente_status);
end;
$$;
revoke all on function privado.registrar_presenca(text, double precision, double precision, timestamptz) from public, anon;
grant execute on function privado.registrar_presenca(text, double precision, double precision, timestamptz) to authenticated;

create or replace function public.minha_escola()
returns table (id smallint, sigla text, nome text, endereco text, telefone text,
               latitude double precision, longitude double precision, raio_m smallint, posicao_confirmada boolean)
language sql stable security invoker set search_path = ''
as $$
  select e.id, e.sigla, e.nome, e.endereco, e.telefone, e.latitude, e.longitude, e.raio_m, e.posicao_confirmada
    from public.escolas e
   where e.id = privado.escola_atual();
$$;
revoke all on function public.minha_escola() from public, anon;
grant execute on function public.minha_escola() to authenticated;
