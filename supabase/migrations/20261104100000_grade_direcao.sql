create or replace function privado.validar_grade(p_oficineiro uuid, p_ano smallint, p_validar boolean, p_comentario text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_e public.grade_envios;
begin
  if not privado.acesso_ok() or privado.papel_atual() is distinct from 'direcao' then perform privado.negar(); end if;
  select * into v_e from public.grade_envios where oficineiro_id = p_oficineiro and ano_letivo = p_ano for update;
  if v_e.id is null or v_e.status <> 'enviada' then perform privado.invalido('não há grade aguardando validação para este oficineiro'); end if;
  if not privado.ve_escola(v_e.escola_id) then perform privado.negar(); end if;
  if not coalesce(p_validar, false) and length(trim(coalesce(p_comentario, ''))) < 5 then
    perform privado.invalido('explique o que o oficineiro precisa ajustar na grade');
  end if;
  update public.grade_envios
     set status = case when p_validar then 'validada' else 'devolvida' end,
         decidido_por = auth.uid(), decidido_em = now(),
         comentario = nullif(left(trim(coalesce(p_comentario, '')), 500), '')
   where id = v_e.id;
end;
$$;

create or replace function privado.enviar_grade(p_ano smallint)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_st text;
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  if not exists (select 1 from public.grade_aulas where oficineiro_id = auth.uid() and ano_letivo = p_ano and escola_id = privado.escola_atual()) then
    perform privado.invalido('a grade deste ano ainda não tem aulas');
  end if;
  select status into v_st from public.grade_envios where oficineiro_id = auth.uid() and ano_letivo = p_ano for update;
  if v_st = 'enviada' then perform privado.invalido('a grade já foi enviada e está aguardando a direção da escola'); end if;
  if v_st = 'validada' then perform privado.invalido('a grade já foi validada'); end if;
  insert into public.grade_envios (oficineiro_id, escola_id, ano_letivo, status)
  values (auth.uid(), privado.escola_atual(), p_ano, 'enviada')
  on conflict (oficineiro_id, ano_letivo) do update
     set status = 'enviada', escola_id = excluded.escola_id, enviado_em = now(),
         decidido_por = null, decidido_em = null, comentario = null;
end;
$$;
