create or replace function privado.recalcular_compensacao(p_oficineiro uuid, p_data date)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_c bigint;
begin
  if p_data is null then return; end if;
  select id into v_c from public.presencas
   where oficineiro_id = p_oficineiro and data = p_data and fim is not null
     and (excedente_status in ('dentro', 'pendente') or compensacao_min > 0);
  if v_c is not null then perform privado.calcular_dia(v_c); end if;
end;
$$;
revoke all on function privado.recalcular_compensacao(uuid, date) from public, anon, authenticated;

create or replace function privado.decidir_deficit(p_id bigint, p_aceitar boolean, p_comentario text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_p public.presencas;
begin
  if privado.papel_atual() is distinct from 'coordenador' or not privado.acesso_ok() then perform privado.negar(); end if;
  if not coalesce(p_aceitar, false) and length(trim(coalesce(p_comentario, ''))) < 5 then
    perform privado.invalido('explique por que a justificativa não foi aceita');
  end if;
  update public.presencas
     set deficit_status = case when p_aceitar then 'autorizado' else 'nao' end,
         deficit_obs = nullif(left(trim(coalesce(p_comentario, '')), 500), ''),
         deficit_decidido_por = auth.uid(), deficit_decidido_em = now()
   where id = p_id and deficit_status = 'aguardando'
  returning * into v_p;
  if v_p.id is null then perform privado.invalido('não há horas abaixo de 8h aguardando decisão neste registro'); end if;
  if not coalesce(p_aceitar, false) then
    perform privado.recalcular_compensacao(v_p.oficineiro_id, v_p.compensar_em);
  end if;
end;
$$;

create or replace function privado.reabrir_presenca(p_id bigint)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_p public.presencas;
  v_n integer;
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  select * into v_p from public.presencas where id = p_id and oficineiro_id = auth.uid() for update;
  if v_p.id is null then perform privado.negar(); end if;
  if v_p.fim is null then perform privado.invalido('esta presença ainda não foi encerrada'); end if;
  if v_p.data <> privado.hoje() then perform privado.invalido('só é possível desfazer o encerramento no mesmo dia'); end if;
  if not privado.mes_editavel(v_p.oficineiro_id, v_p.data) then perform privado.invalido('mês fechado: peça a devolução do relatório'); end if;
  if coalesce(v_p.trabalhado_min, privado.minutos_trabalhados(v_p.inicio, v_p.fim)) >= 480 then
    perform privado.invalido('o dia já tem 8 horas ou mais: o encerramento não pode ser desfeito');
  end if;
  select count(*) into v_n from public.presenca_reaberturas where presenca_id = v_p.id;
  if v_n >= 2 then perform privado.invalido('o encerramento deste dia já foi desfeito 2 vezes'); end if;
  insert into public.presenca_reaberturas (presenca_id, oficineiro_id, escola_id, data, inicio, fim_anterior, trabalhado_min)
  values (v_p.id, v_p.oficineiro_id, v_p.escola_id, v_p.data, v_p.inicio, v_p.fim, coalesce(v_p.trabalhado_min, privado.minutos_trabalhados(v_p.inicio, v_p.fim)));
  update public.presencas
     set fim = null, distancia_fim_m = null, trabalhado_min = null, previsto_min = null,
         compensacao_min = 0, excedente_min = 0, excedente_status = 'dentro',
         deficit_min = 0, deficit_status = 'dentro', motivo_deficit = null, justificativa_deficit = null, compensar_em = null
   where id = v_p.id;
  perform privado.recalcular_compensacao(v_p.oficineiro_id, v_p.compensar_em);
end;
$$;
