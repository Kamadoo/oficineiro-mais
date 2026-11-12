alter table public.perfis add column if not exists documento_tipo text;
alter table public.perfis drop constraint if exists perfis_documento_tipo_check;
alter table public.perfis add constraint perfis_documento_tipo_check check (documento_tipo is null or documento_tipo in ('CPF', 'CNPJ'));
grant select (documento_tipo) on public.perfis to authenticated;

create or replace function privado.documento_normalizado(p_doc text)
returns text
language sql immutable set search_path = ''
as $$
  select case when length(d) between 10 and 11 then privado.cpf_normalizado(d)
              when length(d) = 14 then privado.cnpj_normalizado(d) end
    from (select regexp_replace(coalesce(p_doc, ''), '\D', '', 'g') as d) x;
$$;

create or replace function privado.ciclo_tipo(p_pessoa uuid)
returns text
language sql stable security definer set search_path = ''
as $$
  select coalesce((select 'mensal' from public.perfis p
                    where p.id = p_pessoa and p.papel::text = 'oficineiro' and p.documento_tipo = 'CPF'), 'dia21');
$$;

create or replace function privado.ciclo_de(p_data date, p_tipo text)
returns date
language sql immutable set search_path = ''
as $$
  select case when p_tipo = 'mensal' then date_trunc('month', p_data)::date else privado.ciclo_de(p_data) end;
$$;

create or replace function privado.ciclo_inicio(p_competencia date, p_tipo text)
returns date
language sql immutable set search_path = ''
as $$
  select case when p_tipo = 'mensal' then date_trunc('month', p_competencia)::date else privado.ciclo_inicio(p_competencia) end;
$$;

create or replace function privado.ciclo_fim(p_competencia date, p_tipo text)
returns date
language sql immutable set search_path = ''
as $$
  select case when p_tipo = 'mensal' then (date_trunc('month', p_competencia) + interval '1 month - 1 day')::date
              else privado.ciclo_fim(p_competencia) end;
$$;

create or replace function privado.contratadas_escola()
returns table(id uuid, tipo text, mascara text)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not privado.acesso_ok() or privado.papel_atual() not in ('direcao', 'coordenador', 'gerente') then perform privado.negar(); end if;
  return query
    select p.id, p.contratada_tipo, p.contratada_mascara
      from public.perfis p
     where p.papel::text = 'oficineiro' and p.contratada_tipo is not null and privado.ve_escola(p.escola_id);
end;
$$;

create or replace function public.contratadas_escola()
returns table(id uuid, tipo text, mascara text)
language sql stable security invoker set search_path = ''
as $$ select * from privado.contratadas_escola() $$;

revoke all on function privado.contratadas_escola(), public.contratadas_escola() from public, anon;
grant execute on function privado.contratadas_escola(), public.contratadas_escola() to authenticated;

create or replace function public.meu_ciclo()
returns text language sql stable security invoker set search_path = ''
as $$ select privado.ciclo_tipo(auth.uid()) $$;

revoke all on function privado.documento_normalizado(text) from public, anon, authenticated;
revoke all on function public.meu_ciclo() from public, anon;
grant execute on function public.meu_ciclo() to authenticated;
revoke all on function privado.ciclo_tipo(uuid), privado.ciclo_de(date, text), privado.ciclo_inicio(date, text),
  privado.ciclo_fim(date, text) from public, anon;
grant execute on function privado.ciclo_tipo(uuid), privado.ciclo_de(date, text), privado.ciclo_inicio(date, text),
  privado.ciclo_fim(date, text) to authenticated;

create or replace function public.fsm_conta_por_cpf(p_cpf text)
returns table (user_id uuid, email text, ativo boolean, primeiro_acesso boolean)
language plpgsql stable security definer set search_path = ''
as $$
declare d text := privado.documento_normalizado(p_cpf);
begin
  if d is null then return; end if;
  return query
    select p.id, u.email::text, p.ativo, (p.usuario is null or p.trocar_senha)
      from public.perfis p join auth.users u on u.id = p.id
     where p.cpf_hash = privado.cpf_hash(d);
end;
$$;

create or replace function public.fsm_definir_cpf(p_user uuid, p_cpf text)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  d text := privado.documento_normalizado(p_cpf);
  v_tipo text := case when length(d) = 14 then 'CNPJ' else 'CPF' end;
  v_mascara text;
begin
  if d is null then raise exception 'documento inválido' using errcode = '22023'; end if;
  if exists (select 1 from public.perfis where cpf_hash = privado.cpf_hash(d) and id <> p_user) then
    raise exception 'documento já cadastrado em outra conta' using errcode = '23505';
  end if;
  v_mascara := privado.contratada_mascara(v_tipo, d);
  update public.perfis
     set cpf_cifrado = privado.cpf_cifrar(d), cpf_hash = privado.cpf_hash(d), cpf_mascara = v_mascara,
         documento_tipo = v_tipo
   where id = p_user;
  if not found then raise exception 'conta não encontrada' using errcode = '22023'; end if;
  update public.perfis
     set contratada_tipo = v_tipo, contratada_cifrado = privado.cpf_cifrar(d), contratada_mascara = v_mascara
   where id = p_user and papel::text = 'oficineiro' and contratada_tipo is null;
  return v_mascara;
end;
$$;

create or replace function privado.admin_consulta(p_usuario uuid, p_competencia date)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_t text := privado.ciclo_tipo(p_usuario);
  v_comp date := case when p_competencia is null then privado.ciclo_de(privado.hoje(), v_t)
                      else date_trunc('month', p_competencia)::date end;
  v_ini date := privado.ciclo_inicio(v_comp, v_t);
  v_fim date := privado.ciclo_fim(v_comp, v_t) + 1;
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
  v_t text := privado.ciclo_tipo(p_oficineiro);
begin
  if not privado.eh_admin() then perform privado.negar(); end if;
  v_motivo := privado.admin_motivo(p_motivo);
  select * into v_of from public.perfis where id = p_oficineiro;
  if v_of.id is null or v_of.papel::text <> 'oficineiro' then perform privado.invalido('escolha uma conta de oficineiro'); end if;
  if p_competencia is null or v_comp > privado.ciclo_de(privado.hoje(), v_t) then perform privado.invalido('escolha um ciclo que já começou'); end if;
  select * into v_m from public.relatorios_mensais where oficineiro_id = v_of.id and competencia = v_comp for update;
  if v_m.id is not null and v_m.status = 'devolvido' then perform privado.invalido('este ciclo já está aberto para correção'); end if;
  if v_m.id is null then
    if v_comp = privado.ciclo_de(privado.hoje(), v_t) then perform privado.invalido('o ciclo atual já está aberto'); end if;
    insert into public.relatorios_mensais (oficineiro_id, escola_id, competencia, status, motivo_devolucao)
    values (v_of.id, v_of.escola_id, v_comp, 'devolvido', v_motivo);
  else
    update public.relatorios_mensais set status = 'devolvido', motivo_devolucao = v_motivo where id = v_m.id;
  end if;
  perform privado.admin_correcao('relatorios_mensais', v_of.id::text, v_motivo,
    jsonb_build_object('competencia', v_comp, 'status', jsonb_build_object('de', coalesce(v_m.status, 'fechado'), 'para', 'devolvido')));
end;
$$;

create or replace function privado.assinar_espelho(p_competencia date)
returns timestamptz
language plpgsql security definer set search_path = ''
as $$
declare
  v_comp date := date_trunc('month', p_competencia)::date;
  v_em timestamptz;
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  if p_competencia is null or privado.ciclo_inicio(v_comp, privado.ciclo_tipo(auth.uid())) > privado.hoje() then
    perform privado.invalido('escolha um mês já iniciado');
  end if;
  insert into public.espelho_assinaturas (oficineiro_id, competencia) values (auth.uid(), v_comp)
  on conflict (oficineiro_id, competencia) do nothing
  returning assinado_em into v_em;
  if v_em is null then perform privado.invalido('este espelho já foi assinado'); end if;
  return v_em;
end;
$$;

create or replace function privado.enviar_lembrete(p_grade_aula_id bigint, p_data date)
returns timestamptz
language plpgsql security definer set search_path = ''
as $$
declare
  g public.grade_aulas;
  v_ult timestamptz;
  v_t text;
begin
  if privado.papel_atual() is distinct from 'coordenador' or not privado.acesso_ok() or privado.eh_admin() then perform privado.negar(); end if;
  select * into g from public.grade_aulas where id = p_grade_aula_id;
  if g.id is null or not privado.ve_escola(g.escola_id) then perform privado.negar(); end if;
  v_t := privado.ciclo_tipo(g.oficineiro_id);
  if p_data is null or p_data > privado.hoje() then perform privado.invalido('a aula ainda não aconteceu'); end if;
  if privado.ciclo_de(p_data, v_t) <> privado.ciclo_de(privado.hoje(), v_t) then
    perform privado.invalido('o ciclo desta aula já terminou e ela não pode mais ser registrada');
  end if;
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

create or replace function privado.espelho_oficineiro(p_oficineiro uuid, p_competencia date default null)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_t text := privado.ciclo_tipo(p_oficineiro);
  v_comp date := coalesce(date_trunc('month', p_competencia)::date, privado.ciclo_de(privado.hoje(), v_t));
begin
  if not privado.acesso_ok() or privado.papel_atual() not in ('direcao', 'coordenador', 'gerente') then perform privado.negar(); end if;
  if not exists (select 1 from public.perfis p where p.id = p_oficineiro and p.papel = 'oficineiro' and privado.ve_escola(p.escola_id)) then
    perform privado.invalido('oficineiro não encontrado');
  end if;
  return jsonb_build_object(
    'competencia', v_comp,
    'ciclo', v_t,
    'inicio', privado.ciclo_inicio(v_comp, v_t),
    'fim', privado.ciclo_fim(v_comp, v_t),
    'assinado_em', (select a.assinado_em from public.espelho_assinaturas a where a.oficineiro_id = p_oficineiro and a.competencia = v_comp),
    'dias', coalesce((select jsonb_agg(to_jsonb(x)) from privado.espelho_dias(p_oficineiro, privado.ciclo_inicio(v_comp, v_t), privado.ciclo_fim(v_comp, v_t)) x), '[]'::jsonb));
end;
$$;

create or replace function privado.fechar_relatorio(p_competencia date)
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare
  v_comp date := date_trunc('month', p_competencia)::date;
  v_t text := privado.ciclo_tipo(auth.uid());
  v_id bigint;
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  if v_comp > privado.ciclo_de(privado.hoje(), v_t) then perform privado.invalido('não é possível fechar um ciclo futuro'); end if;
  if v_comp >= privado.ciclo_de(privado.hoje(), v_t)
     and not exists (select 1 from public.relatorios_mensais r
                      where r.oficineiro_id = auth.uid() and r.competencia = v_comp and r.status = 'devolvido') then
    perform privado.invalido('o ciclo ainda não terminou: ele fecha sozinho depois do último dia');
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

create or replace function privado.garantir_relatorios(p_competencia date)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_comp date := date_trunc('month', p_competencia)::date;
begin
  insert into public.relatorios_mensais (oficineiro_id, escola_id, competencia, status, fechado_em)
  select p.id, p.escola_id, v_comp, 'fechado', (c.fim::timestamp at time zone 'America/Sao_Paulo')
    from public.perfis p
    cross join lateral (
      select t, privado.ciclo_inicio(v_comp, t) as ini, privado.ciclo_fim(v_comp, t) + 1 as fim
        from (select privado.ciclo_tipo(p.id) as t) x
    ) c
   where p.papel::text = 'oficineiro'
     and p.escola_id is not null
     and privado.ve_escola(p.escola_id)
     and v_comp < privado.ciclo_de(privado.hoje(), c.t)
     and (exists (select 1 from public.presencas x where x.oficineiro_id = p.id and x.data >= c.ini and x.data < c.fim)
          or exists (select 1 from public.aulas_registro x where x.oficineiro_id = p.id and x.data >= c.ini and x.data < c.fim)
          or exists (select 1 from public.grade_aulas g
                      where g.oficineiro_id = p.id
                        and g.ano_letivo between extract(year from c.ini) and extract(year from c.fim - 1)
                        and g.criado_em < (c.fim::timestamp at time zone 'America/Sao_Paulo')))
  on conflict (oficineiro_id, competencia) do nothing;
end;
$$;

create or replace function privado.mes_editavel(p_oficineiro uuid, p_data date)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select p_data <= privado.hoje()
     and not exists (select 1 from public.relatorios_mensais r
                     where r.oficineiro_id = p_oficineiro
                       and r.competencia = privado.ciclo_de(p_data, t.t)
                       and r.status <> 'devolvido')
     and (privado.ciclo_de(p_data, t.t) = privado.ciclo_de(privado.hoje(), t.t)
          or exists (select 1 from public.relatorios_mensais r
                     where r.oficineiro_id = p_oficineiro
                       and r.competencia = privado.ciclo_de(p_data, t.t)
                       and r.status = 'devolvido'))
    from (select privado.ciclo_tipo(p_oficineiro) as t) t;
$$;

create or replace function privado.meu_espelho(p_competencia date default null)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_t text := privado.ciclo_tipo(auth.uid());
  v_comp date := coalesce(date_trunc('month', p_competencia)::date, privado.ciclo_de(privado.hoje(), v_t));
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  return jsonb_build_object(
    'competencia', v_comp,
    'ciclo', v_t,
    'inicio', privado.ciclo_inicio(v_comp, v_t),
    'fim', privado.ciclo_fim(v_comp, v_t),
    'assinado_em', (select a.assinado_em from public.espelho_assinaturas a where a.oficineiro_id = v_uid and a.competencia = v_comp),
    'dias', coalesce((select jsonb_agg(to_jsonb(x)) from privado.espelho_dias(v_uid, privado.ciclo_inicio(v_comp, v_t), privado.ciclo_fim(v_comp, v_t)) x), '[]'::jsonb));
end;
$$;

create or replace function privado.meus_lembretes()
returns table(id bigint, grade_aula_id bigint, data date, enviado_em timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_t text := privado.ciclo_tipo(auth.uid());
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  return query
    select l.id, l.grade_aula_id, l.data, l.enviado_em
      from public.lembretes_registro l
     where l.oficineiro_id = auth.uid()
       and privado.ciclo_de(l.data, v_t) = privado.ciclo_de(privado.hoje(), v_t)
       and not exists (select 1 from public.aulas_registro r where r.grade_aula_id = l.grade_aula_id and r.data = l.data)
     order by l.data;
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
           where x.oficineiro_id = r.oficineiro_id and x.data >= c.ini and x.data < c.fim and x.fim is not null),
         privado.horas_validas(r.oficineiro_id, c.ini, c.fim - 1),
         a.registradas, a.realizadas, a.nao_realizadas, a.confirmadas, a.contestadas, a.estudantes
    from public.relatorios_mensais r
    join public.perfis o on o.id = r.oficineiro_id
    join public.escolas e on e.id = r.escola_id
    left join public.perfis pd on pd.id = r.direcao_por
    left join public.perfis pc on pc.id = r.coordenacao_por
    left join public.perfis pv on pv.id = r.devolvido_por
    cross join lateral (
      select privado.ciclo_inicio(v_comp, t) as ini, privado.ciclo_fim(v_comp, t) + 1 as fim
        from (select privado.ciclo_tipo(r.oficineiro_id) as t) x
    ) c
    cross join lateral (
      select count(*) filter (where x.situacao in ('Realizada', 'Realizada parcialmente', 'Não realizada'))::integer as registradas,
             count(*) filter (where x.situacao in ('Realizada', 'Realizada parcialmente'))::integer as realizadas,
             count(*) filter (where x.situacao = 'Não realizada')::integer as nao_realizadas,
             count(*) filter (where x.check_direcao = 'ok')::integer as confirmadas,
             count(*) filter (where x.check_direcao = 'contestada')::integer as contestadas,
             coalesce(sum(x.presentes) filter (where x.situacao in ('Realizada', 'Realizada parcialmente')), 0)::integer as estudantes
        from public.aulas_registro x
       where x.oficineiro_id = r.oficineiro_id and x.data >= c.ini and x.data < c.fim
         and x.revisao_status is distinct from 'anulado'
    ) a
   where r.competencia = v_comp
     and privado.ve_escola(r.escola_id)
   order by e.sigla, o.nome;
end;
$$;

create or replace function privado.solicitar_ajuste(p_tipo text, p_data date, p_entrada time, p_saida_almoco time,
                                                    p_retorno_almoco time, p_saida time, p_motivo text)
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_t text := privado.ciclo_tipo(auth.uid());
  v_p public.presencas;
  v_id bigint;
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  if p_tipo not in ('falta', 'esquecimento', 'fora_raio', 'almoco', 'externa') then perform privado.invalido('tipo de solicitação inválido'); end if;
  if p_data is null or p_data > privado.hoje() then perform privado.invalido('escolha uma data até hoje'); end if;
  if p_data < privado.ciclo_inicio(privado.ciclo_de(privado.hoje(), v_t), v_t) then
    perform privado.invalido('o prazo para justificar este dia terminou no fechamento do ciclo');
  end if;
  if length(trim(coalesce(p_motivo, ''))) < 5 then perform privado.invalido('explique o motivo da solicitação'); end if;
  if p_tipo <> 'falta' then
    select * into v_p from public.presencas where oficineiro_id = v_uid and data = p_data;
    perform privado.horarios_ajustados(v_p, p_data, p_entrada, p_saida_almoco, p_retorno_almoco, p_saida);
  end if;
  if exists (select 1 from public.presenca_ajustes where oficineiro_id = v_uid and data = p_data and status = 'em_analise') then
    perform privado.invalido('já existe uma solicitação em análise para este dia');
  end if;
  insert into public.presenca_ajustes (oficineiro_id, escola_id, data, tipo, entrada, saida_almoco, retorno_almoco, saida, motivo)
  values (v_uid, coalesce(v_p.escola_id, privado.escola_atual()), p_data, p_tipo,
          case when p_tipo <> 'falta' then p_entrada end, case when p_tipo <> 'falta' then p_saida_almoco end,
          case when p_tipo <> 'falta' then p_retorno_almoco end, case when p_tipo <> 'falta' then p_saida end,
          left(trim(p_motivo), 1000))
  returning id into v_id;
  return v_id;
end;
$$;
