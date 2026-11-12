create index if not exists eventos_acao_em on auditoria.eventos (acao, em desc);

create or replace function auditoria.trigger_acesso()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.last_sign_in_at is not null and new.last_sign_in_at is distinct from old.last_sign_in_at
     and not exists (select 1 from auditoria.eventos
                      where usuario_id = new.id and acao = 'ACESSO' and em > now() - interval '2 minutes') then
    insert into auditoria.eventos (usuario_id, papel, acao, registro)
    select p.id, p.papel::text, 'ACESSO', p.id::text from public.perfis p where p.id = new.id;
  end if;
  return new;
exception when others then
  return new;
end;
$$;
revoke all on function auditoria.trigger_acesso() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'auth' and table_name = 'users' and column_name = 'last_sign_in_at') then
    drop trigger if exists fsm_registrar_acesso on auth.users;
    create trigger fsm_registrar_acesso after update of last_sign_in_at on auth.users
      for each row execute function auditoria.trigger_acesso();
  end if;
exception when insufficient_privilege then
  raise notice 'sem permissão para criar o registro de acessos em auth.users';
end $$;

create or replace function privado.texto_seguro(p_valor text, p_max integer)
returns text
language sql immutable set search_path = ''
as $$
  select nullif(left(regexp_replace(regexp_replace(btrim(coalesce(p_valor, '')), '\d{3}\.?\d{3}\.?\d{3}-?\d{2}', '***', 'g'),
                                    '[[:cntrl:]]', ' ', 'g'), p_max), '');
$$;
revoke all on function privado.texto_seguro(text, integer) from public, anon, authenticated;

create or replace function privado.registrar_atividade(p_tipo text, p_detalhes jsonb default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_acao text := upper(coalesce(p_tipo, ''));
  d jsonb := case when jsonb_typeof(p_detalhes) = 'object' then p_detalhes else '{}'::jsonb end;
  v jsonb;
begin
  if v_uid is null or not privado.acesso_ok() then perform privado.negar(); end if;
  if v_acao not in ('CONSULTA', 'EXPORTACAO', 'PRESENCA_RECUSADA') then perform privado.invalido('tipo de atividade inválido'); end if;
  if length(d::text) > 4000 then perform privado.invalido('detalhes da atividade muito longos'); end if;

  v := jsonb_strip_nulls(jsonb_build_object(
    'tela', privado.texto_seguro(d ->> 'tela', 80),
    'descricao', privado.texto_seguro(d ->> 'descricao', 200),
    'arquivo', privado.texto_seguro(d ->> 'arquivo', 120),
    'formato', privado.texto_seguro(d ->> 'formato', 30),
    'linhas', case when jsonb_typeof(d -> 'linhas') = 'number' then least(greatest((d ->> 'linhas')::numeric, 0), 1000000)::integer end,
    'alvo', case when d ->> 'alvo' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then lower(d ->> 'alvo') end,
    'escola_id', case when jsonb_typeof(d -> 'escola_id') = 'number' and (d ->> 'escola_id') ~ '^\d{1,5}$' then (d ->> 'escola_id')::integer end,
    'periodo', privado.texto_seguro(d ->> 'periodo', 60),
    'filtros', privado.texto_seguro(d ->> 'filtros', 200),
    'evento', privado.texto_seguro(d ->> 'evento', 30),
    'motivo', privado.texto_seguro(d ->> 'motivo', 200),
    'distancia_m', case when jsonb_typeof(d -> 'distancia_m') = 'number' then least(greatest((d ->> 'distancia_m')::numeric, 0), 100000000)::integer end,
    'quando', case when (d ->> 'quando') ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}' then left(d ->> 'quando', 35) end
  ));

  if exists (select 1 from auditoria.eventos
              where usuario_id = v_uid and acao = v_acao and em > now() - interval '1 minute'
                and detalhes is not distinct from v) then
    return;
  end if;
  if (select count(*) from auditoria.eventos
       where usuario_id = v_uid and acao = v_acao and em > now() - interval '1 hour') >= 300 then
    return;
  end if;

  perform auditoria.registrar(v_acao, null, null, v);
end;
$$;

create or replace function privado.atividade_evento(p_acao text, p_tabela text, p_papel text, d jsonb)
returns text
language sql immutable set search_path = ''
as $$
  select case
    when p_acao = 'ACESSO' then 'acesso'
    when p_acao = 'CONSULTA' then 'consulta'
    when p_acao = 'REVELAR_CPF' then 'cpf'
    when p_acao = 'EXPORTACAO' then 'exportacao'
    when p_acao = 'PRESENCA_RECUSADA' then 'recusa'
    when p_acao in ('CADASTRAR_USUARIO', 'DESATIVAR_USUARIO', 'REATIVAR_USUARIO', 'ADMIN_ALTERAR_PERFIL',
                    'ADMIN_EXIGIR_TROCA_SENHA', 'ADMIN_REDEFINIR_AUTENTICADOR', 'ADMIN_CORRECAO', 'IMPORTAR_OS') then lower(p_acao)
    when p_tabela in ('presencas', 'presencas_analista') then case
      when p_acao = 'INSERT' then 'entrada'
      when p_acao <> 'UPDATE' then null
      when d ? 'fim' and d -> 'fim' ->> 'de' is null and d -> 'fim' ->> 'para' is not null then 'saida'
      when d ? 'entrou_raio_em' and d -> 'entrou_raio_em' ->> 'de' is null and d -> 'entrou_raio_em' ->> 'para' is not null then 'entrada_raio'
      when p_papel = 'oficineiro'
           and d ?| array['justificativa', 'justificativa_excedente', 'justificativa_deficit', 'justificativa_horario'] then 'justificativa'
      when p_papel not in ('oficineiro', 'analista')
           and d ?| array['conferencia_status', 'excedente_status', 'deficit_status', 'horario_status'] then 'decisao_presenca'
    end
    when p_tabela = 'presenca_reaberturas' and p_acao = 'INSERT' then 'reabertura'
    when p_tabela = 'aulas_registro' then case
      when p_acao = 'INSERT' then 'aula_registrada'
      when p_acao = 'DELETE' then 'aula_excluida'
      when p_papel = 'oficineiro' then 'aula_editada'
      when p_papel = 'direcao' and d ? 'check_direcao' then 'aula_direcao'
      when d ? 'revisao_status' and d -> 'revisao_status' ->> 'para' is not null then 'aula_revisada'
    end
    when p_tabela = 'grade_envios' then case
      when p_acao = 'INSERT' or (d ? 'status' and d -> 'status' ->> 'para' = 'enviada') then 'grade_enviada'
      when d -> 'status' ->> 'para' = 'validada' then 'grade_validada'
      when d -> 'status' ->> 'para' = 'devolvida' then 'grade_devolvida'
    end
    when p_tabela = 'relatorios_mensais' then case
      when p_acao = 'INSERT' or d -> 'status' ->> 'para' = 'fechado' then 'relatorio_fechado'
      when d -> 'status' ->> 'para' in ('aprovado_direcao', 'aprovado_coordenacao') then 'relatorio_aprovado'
      when d -> 'status' ->> 'para' = 'devolvido' then 'relatorio_devolvido'
    end
    when p_tabela = 'visitas' then case
      when p_acao = 'INSERT' then 'visita_registrada'
      when p_acao = 'UPDATE' and p_papel = 'analista' then 'visita_corrigida'
    end
    when p_tabela = 'visitas_agenda' then case
      when p_acao = 'INSERT' then 'visita_agendada'
      when d -> 'status' ->> 'para' = 'cancelada' then 'visita_cancelada'
      when d ? 'data' then 'visita_remarcada'
    end
    when p_tabela = 'onboarding_itens' and d ? 'status' then case
      when d -> 'status' ->> 'para' = 'concluido' then 'onboarding_baixa'
      when d -> 'status' ->> 'para' = 'pendente' then 'onboarding_reaberto'
    end
  end;
$$;

create or replace function privado.atividade_categoria(p_evento text)
returns text
language sql immutable set search_path = ''
as $$
  select case
    when p_evento is null then null
    when p_evento = 'acesso' then 'acesso'
    when p_evento in ('entrada', 'saida', 'entrada_raio', 'justificativa', 'reabertura') then 'presenca'
    when p_evento = 'recusa' then 'recusa'
    when p_evento in ('consulta', 'cpf') then 'consulta'
    when p_evento = 'exportacao' then 'exportacao'
    when p_evento in ('decisao_presenca', 'aula_direcao', 'aula_revisada', 'grade_validada', 'grade_devolvida',
                      'relatorio_aprovado', 'relatorio_devolvido') then 'conferencia'
    when p_evento in ('cadastrar_usuario', 'desativar_usuario', 'reativar_usuario', 'admin_alterar_perfil',
                      'admin_exigir_troca_senha', 'admin_redefinir_autenticador', 'admin_correcao', 'importar_os') then 'administracao'
    else 'registro'
  end;
$$;
revoke all on function privado.atividade_evento(text, text, text, jsonb), privado.atividade_categoria(text) from public, anon, authenticated;

create or replace function privado.admin_atividades(
  p_desde date default null, p_ate date default null, p_usuario uuid default null,
  p_categoria text default null, p_limite integer default 500
)
returns table (id bigint, em timestamptz, usuario_id uuid, nome text, papel text, categoria text, evento text,
               escola_id integer, escola text, alvo_id uuid, alvo_nome text, detalhes jsonb)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not privado.eh_admin() then perform privado.negar(); end if;
  if p_categoria is not null and p_categoria not in ('acesso', 'presenca', 'recusa', 'registro', 'conferencia', 'consulta', 'exportacao', 'administracao') then
    perform privado.invalido('categoria inválida');
  end if;
  return query
    with base as (
      select e.id, e.em, e.usuario_id, e.papel, e.tabela, e.registro, e.detalhes d,
             case when e.registro ~ '^\d{1,18}$' then e.registro::bigint end rid,
             privado.atividade_evento(e.acao, e.tabela, e.papel, e.detalhes) ev
        from auditoria.eventos e
       where (p_desde is null or e.em >= (p_desde::timestamp at time zone 'America/Sao_Paulo'))
         and (p_ate is null or e.em < ((p_ate + 1)::timestamp at time zone 'America/Sao_Paulo'))
         and (p_usuario is null or e.usuario_id = p_usuario)
    ), filtrada as (
      select b.*, privado.atividade_categoria(b.ev) cat
        from base b
       where b.ev is not null
         and (p_categoria is null or privado.atividade_categoria(b.ev) = p_categoria)
       order by b.em desc, b.id desc
       limit least(greatest(coalesce(p_limite, 500), 1), 1000)
    )
    select f.id, f.em, f.usuario_id,
           case when f.usuario_id is null then 'Sistema' else coalesce(pu.nome, 'Conta removida') end,
           coalesce(f.papel, pu.papel::text), f.cat, f.ev,
           x.esc, es.nome, x.alvo, pa.nome, f.d
      from filtrada f
      left join public.perfis pu on pu.id = f.usuario_id
      left join lateral (
        select coalesce(
                 case when jsonb_typeof(f.d -> 'escola_id') = 'number' then (f.d ->> 'escola_id')::integer end,
                 r.escola_id) esc,
               coalesce(
                 case when f.d ->> 'alvo' ~ '^[0-9a-f-]{36}$' then (f.d ->> 'alvo')::uuid end,
                 case when jsonb_typeof(f.d -> 'oficineiro_id') = 'string' then (f.d ->> 'oficineiro_id')::uuid end,
                 case when jsonb_typeof(f.d -> 'analista_id') = 'string' then (f.d ->> 'analista_id')::uuid end,
                 r.dono,
                 case when f.tabela is null and f.registro ~ '^[0-9a-f-]{36}$' then f.registro::uuid end) alvo
          from (select null::integer escola_id, null::uuid dono) z
          left join lateral (
            select p.escola_id::integer escola_id, p.oficineiro_id dono from public.presencas p where f.tabela = 'presencas' and p.id = f.rid
            union all
            select p.escola_id::integer, p.analista_id from public.presencas_analista p where f.tabela = 'presencas_analista' and p.id = f.rid
            union all
            select p.escola_id::integer, p.oficineiro_id from public.presenca_reaberturas p where f.tabela = 'presenca_reaberturas' and p.id = f.rid
            union all
            select a.escola_id::integer, a.oficineiro_id from public.aulas_registro a where f.tabela = 'aulas_registro' and a.id = f.rid
            union all
            select g.escola_id::integer, g.oficineiro_id from public.grade_envios g where f.tabela = 'grade_envios' and g.id = f.rid
            union all
            select m.escola_id::integer, m.oficineiro_id from public.relatorios_mensais m where f.tabela = 'relatorios_mensais' and m.id = f.rid
            union all
            select v.escola_id::integer, v.analista_id from public.visitas v where f.tabela = 'visitas' and v.id = f.rid
            union all
            select v.escola_id::integer, v.analista_id from public.visitas_agenda v where f.tabela = 'visitas_agenda' and v.id = f.rid
            union all
            select o.escola_id::integer, null::uuid from public.onboarding_itens o where f.tabela = 'onboarding_itens' and o.id = f.rid
            limit 1
          ) r on true
      ) x on true
      left join public.escolas es on es.id = x.esc
      left join public.perfis pa on pa.id = x.alvo
     order by f.em desc, f.id desc;
end;
$$;

create or replace function public.registrar_atividade(p_tipo text, p_detalhes jsonb default null)
returns void language sql security invoker set search_path = ''
as $$ select privado.registrar_atividade(p_tipo, p_detalhes) $$;

create or replace function public.admin_atividades(
  p_desde date default null, p_ate date default null, p_usuario uuid default null,
  p_categoria text default null, p_limite integer default 500
)
returns table (id bigint, em timestamptz, usuario_id uuid, nome text, papel text, categoria text, evento text,
               escola_id integer, escola text, alvo_id uuid, alvo_nome text, detalhes jsonb)
language sql stable security invoker set search_path = ''
as $$ select * from privado.admin_atividades(p_desde, p_ate, p_usuario, p_categoria, p_limite) $$;

revoke all on function
  privado.registrar_atividade(text, jsonb), privado.admin_atividades(date, date, uuid, text, integer),
  public.registrar_atividade(text, jsonb), public.admin_atividades(date, date, uuid, text, integer)
  from public, anon;
grant execute on function
  privado.registrar_atividade(text, jsonb), privado.admin_atividades(date, date, uuid, text, integer),
  public.registrar_atividade(text, jsonb), public.admin_atividades(date, date, uuid, text, integer)
  to authenticated;
