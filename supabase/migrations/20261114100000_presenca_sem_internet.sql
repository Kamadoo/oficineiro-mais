drop function if exists public.marcar_presenca(text, double precision, double precision, integer);
drop function if exists privado.marcar_presenca(text, double precision, double precision, integer);

create or replace function privado.marcar_presenca(
  p_tipo text, p_lat double precision, p_lng double precision, p_precisao integer default null, p_quando timestamptz default null
)
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
  v_quando timestamptz := coalesce(p_quando, clock_timestamp());
  v_atraso integer;
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  if p_tipo not in ('entrada', 'saida_almoco', 'retorno_almoco', 'saida') then perform privado.invalido('marcação inválida'); end if;
  if (p_lat is null) <> (p_lng is null) or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    perform privado.invalido('localização inválida');
  end if;
  if p_quando is not null then
    if p_quando > v_agora + interval '2 minutes' then
      perform privado.invalido('a hora da marcação está no futuro; confira o relógio do aparelho');
    end if;
    if p_quando < v_agora - interval '8 hours' then
      perform privado.invalido('marcação feita sem internet há mais de 8 horas; peça o ajuste pelo espelho de presença');
    end if;
    v_quando := least(p_quando, v_agora);
    v_atraso := greatest(0, round(extract(epoch from v_agora - v_quando))::integer);
  end if;

  v_p := privado.jornada_aberta(v_uid);
  if v_p.id is null and exists (select 1 from public.presencas
                                 where oficineiro_id = v_uid and data = (v_quando at time zone 'America/Sao_Paulo')::date) then
    perform privado.invalido('a jornada de hoje já foi encerrada');
  end if;
  v_prox := privado.proxima_marcacao(v_p);
  if not (p_tipo = v_prox or (p_tipo = 'saida' and v_prox = 'saida_almoco')) then
    perform privado.invalido('esta marcação não é a próxima da sequência');
  end if;
  if v_p.id is not null and v_quando <= greatest(v_p.inicio, v_p.pausa_inicio, v_p.pausa_fim) then
    perform privado.invalido('a marcação precisa ser posterior à anterior');
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
    values (v_uid, v_esc.id, (v_quando at time zone 'America/Sao_Paulo')::date, v_quando, v_dist, 'dentro', true)
    returning * into v_p;
  elsif p_tipo = 'saida_almoco' then
    update public.presencas set pausa_inicio = v_quando where id = v_p.id returning * into v_p;
  elsif p_tipo = 'retorno_almoco' then
    update public.presencas set pausa_fim = v_quando where id = v_p.id returning * into v_p;
  else
    update public.presencas set fim = v_quando, distancia_fim_m = v_dist where id = v_p.id returning * into v_p;
    perform privado.calcular_dia(v_p.id);
  end if;

  insert into public.presenca_marcacoes (presenca_id, oficineiro_id, tipo, registrado_em, sem_internet, diferenca_relogio_s,
                                         precisao_m, distancia_m, dentro_raio)
  values (v_p.id, v_uid, p_tipo, v_quando, p_quando is not null, v_atraso, v_prec, v_dist, true)
  on conflict (presenca_id, tipo) do update
     set registrado_em = excluded.registrado_em, recebido_em = now(), sem_internet = excluded.sem_internet,
         diferenca_relogio_s = excluded.diferenca_relogio_s, precisao_m = excluded.precisao_m,
         distancia_m = excluded.distancia_m, dentro_raio = true;

  return jsonb_build_object('aceita', true, 'tipo', p_tipo, 'em', v_quando, 'distancia_m', v_dist,
                            'sem_internet', p_quando is not null);
end;
$$;

create or replace function public.marcar_presenca(
  p_tipo text, p_lat double precision, p_lng double precision, p_precisao integer default null, p_quando timestamptz default null
)
returns jsonb language sql security invoker set search_path = ''
as $$ select privado.marcar_presenca(p_tipo, p_lat, p_lng, p_precisao, p_quando) $$;

revoke all on function privado.marcar_presenca(text, double precision, double precision, integer, timestamptz),
                       public.marcar_presenca(text, double precision, double precision, integer, timestamptz)
  from public, anon;
grant execute on function privado.marcar_presenca(text, double precision, double precision, integer, timestamptz),
                          public.marcar_presenca(text, double precision, double precision, integer, timestamptz)
  to authenticated;
