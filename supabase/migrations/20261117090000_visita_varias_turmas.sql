alter table public.visitas add column if not exists turmas text[]
  check (turmas is null or (cardinality(turmas) between 1 and 12 and array_position(turmas, null) is null));

update public.visitas set turmas = array[turma] where turma is not null and turmas is null;

create or replace function privado.turmas_da_visita(p jsonb)
returns text[]
language plpgsql stable set search_path = ''
as $$
declare v_lista text[] := '{}'; v_item text; v_t text;
begin
  if jsonb_typeof(p -> 'turmas') = 'array' then
    for v_item in select x from jsonb_array_elements_text(p -> 'turmas') with ordinality as e(x, n) order by n loop
      v_t := nullif(trim(coalesce(v_item, '')), '');
      if v_t is null then continue; end if;
      if length(v_t) > 60 then perform privado.invalido('nome de turma muito longo'); end if;
      if not v_t = any(v_lista) then v_lista := v_lista || v_t; end if;
    end loop;
  elsif p ? 'turmas' and jsonb_typeof(p -> 'turmas') <> 'null' then
    perform privado.invalido('lista de turmas inválida');
  else
    v_t := nullif(left(trim(coalesce(p ->> 'turma', '')), 60), '');
    if v_t is not null then v_lista := array[v_t]; end if;
  end if;
  if cardinality(v_lista) > 12 then perform privado.invalido('escolha no máximo 12 turmas por visita'); end if;
  return nullif(v_lista, '{}');
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
  v.turmas := privado.turmas_da_visita(p);
  v.turma := v.turmas[1];
  v.oficineiro_id := nullif(p ->> 'oficineiro', '')::uuid;
  if v.escola_id is null then perform privado.invalido('escolha a escola da visita'); end if;
  if not privado.ve_escola(v.escola_id) then perform privado.invalido('esta escola não é da sua carteira'); end if;
  if v.data is null or v.data > privado.hoje() then perform privado.invalido('a data da visita não pode ser futura'); end if;
  if coalesce(v.tipo, '') not in ('Suporte', 'Implantação', 'Acompanhamento', 'Formação') then
    perform privado.invalido('escolha o tipo de atendimento');
  end if;
  if length(coalesce(v.observacao, '')) < 10 then perform privado.invalido('descreva como foi a visita'); end if;
  if v.objetivo is not null and v.objetivo not in ('Sim', 'Não') then perform privado.invalido('objetivo inválido'); end if;
  if v.engajamento is not null and v.engajamento not between 1 and 5 then perform privado.invalido('engajamento inválido'); end if;
  if privado.visita_com_alunos(v.subtipo) then
    if v.turmas is null or v.oficineiro_id is null then
      perform privado.invalido('escolha a turma e o oficineiro atendidos');
    end if;
    if not exists (select 1 from public.perfis o where o.id = v.oficineiro_id and o.papel = 'oficineiro'
                     and (o.escola_id = v.escola_id
                          or exists (select 1 from public.grade_aulas g where g.oficineiro_id = o.id and g.escola_id = v.escola_id))) then
      perform privado.invalido('o oficineiro escolhido não atua nesta escola');
    end if;
  else
    v.turma := null;
    v.turmas := null;
    v.oficineiro_id := null;
  end if;
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
                              objetivo, engajamento, boas_praticas, dificuldades, ocorrencias, ocorrencia_obs, agenda_id, presenca_id,
                              turma, turmas, oficineiro_id)
  values (auth.uid(), v.escola_id, v.data, v.tipo, v.subtipo, v.participantes, v.solucao, v.observacao,
          v.objetivo, v.engajamento, v.boas_praticas, v.dificuldades, v.ocorrencias, v.ocorrencia_obs, v_ag.id, v_pr.id,
          v.turma, v.turmas, v.oficineiro_id)
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
         dificuldades = v.dificuldades, ocorrencias = v.ocorrencias, ocorrencia_obs = v.ocorrencia_obs,
         turma = v.turma, turmas = v.turmas, oficineiro_id = v.oficineiro_id, editado_em = now()
   where id = p_id;
end;
$$;

revoke all on function privado.turmas_da_visita(jsonb) from public, anon, authenticated;
