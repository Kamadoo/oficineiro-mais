create or replace function privado.grade_sem_conflito()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if exists (
    select 1
      from public.grade_aulas g
     where g.oficineiro_id = new.oficineiro_id
       and g.escola_id = new.escola_id
       and g.id is distinct from new.id
       and g.ano_letivo = new.ano_letivo
       and g.dia_semana = new.dia_semana
       and g.inicio < new.fim and new.inicio < g.fim
  ) then
    raise exception 'já existe uma aula sua neste horário' using errcode = '22023';
  end if;
  return new;
end;
$$;
revoke all on function privado.grade_sem_conflito() from public, anon;

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
  if v_st = 'enviada' then perform privado.invalido('a grade já foi enviada e está aguardando o coordenador'); end if;
  if v_st = 'validada' then perform privado.invalido('a grade já foi validada'); end if;
  insert into public.grade_envios (oficineiro_id, escola_id, ano_letivo, status)
  values (auth.uid(), privado.escola_atual(), p_ano, 'enviada')
  on conflict (oficineiro_id, ano_letivo) do update
     set status = 'enviada', escola_id = excluded.escola_id, enviado_em = now(),
         decidido_por = null, decidido_em = null, comentario = null;
end;
$$;
