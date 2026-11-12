create or replace function privado.nomes_da_escola()
returns table (id uuid, nome text)
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_esc smallint;
begin
  if not privado.acesso_ok() or privado.papel_atual() <> 'direcao' then perform privado.negar(); end if;
  v_esc := privado.escola_atual();
  return query
  select p.id, p.nome
    from public.perfis p
   where p.papel = 'oficineiro'
     and (exists (select 1 from public.presencas x where x.oficineiro_id = p.id and x.escola_id = v_esc)
       or exists (select 1 from public.aulas_registro x where x.oficineiro_id = p.id and x.escola_id = v_esc))
   order by p.nome;
end;
$$;

create or replace function privado.admin_atividades(p_desde date DEFAULT NULL::date, p_ate date DEFAULT NULL::date, p_usuario uuid DEFAULT NULL::uuid, p_categoria text DEFAULT NULL::text, p_limite integer DEFAULT 500)
returns table (id bigint, em timestamp with time zone, usuario_id uuid, nome text, papel text, categoria text, evento text, escola_id integer, escola text, alvo_id uuid, alvo_nome text, detalhes jsonb)
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

drop function if exists public.registrar_presenca(text, double precision, double precision, timestamptz);
drop function if exists public.registrar_marcacao(text, double precision, double precision, timestamptz, timestamptz, integer, smallint, boolean, text, text);
drop function if exists public.registrar_entrada_raio(double precision, double precision, timestamptz);
drop function if exists public.justificar_marcacao(bigint, text, jsonb, text);
drop function if exists public.decidir_marcacao(bigint, boolean, text);
drop function if exists public.justificar_excedente(bigint, text, text);
drop function if exists public.decidir_excedente(bigint, boolean);
drop function if exists public.decidir_excedente(bigint, boolean, text);
drop function if exists public.justificar_deficit(bigint, text, text, date);
drop function if exists public.decidir_deficit(bigint, boolean, text);
drop function if exists public.justificar_horario(bigint, text, text);
drop function if exists public.decidir_horario(bigint, boolean, text);
drop function if exists public.justificar_presenca(bigint, text, text);
drop function if exists public.conferir_presenca(bigint, boolean, text);
drop function if exists public.reabrir_presenca(bigint);
drop function if exists public.banco_horas(date);
drop function if exists public.pedir_folga(date, integer, text);
drop function if exists public.cancelar_folga(bigint);
drop function if exists public.decidir_folga(bigint, boolean, text);
drop function if exists public.definir_jornada(uuid, time);
drop function if exists public.admin_situacao_presenca(bigint, text, text, text);

drop function if exists privado.registrar_presenca(text, double precision, double precision, timestamptz);
drop function if exists privado.registrar_marcacao(text, double precision, double precision, timestamptz, timestamptz, integer, smallint, boolean, text, text);
drop function if exists privado.registrar_entrada_raio(double precision, double precision, timestamptz);
drop function if exists privado.justificar_marcacao(bigint, text, jsonb, text);
drop function if exists privado.decidir_marcacao(bigint, boolean, text);
drop function if exists privado.justificar_excedente(bigint, text, text);
drop function if exists privado.decidir_excedente(bigint, boolean);
drop function if exists privado.decidir_excedente(bigint, boolean, text);
drop function if exists privado.justificar_deficit(bigint, text, text, date);
drop function if exists privado.decidir_deficit(bigint, boolean, text);
drop function if exists privado.justificar_horario(bigint, text, text);
drop function if exists privado.decidir_horario(bigint, boolean, text);
drop function if exists privado.justificar_presenca(bigint, text, text);
drop function if exists privado.conferir_presenca(bigint, boolean, text);
drop function if exists privado.reabrir_presenca(bigint);
drop function if exists privado.banco_horas(date);
drop function if exists privado.banco_do(uuid, date);
drop function if exists privado.pedir_folga(date, integer, text);
drop function if exists privado.cancelar_folga(bigint);
drop function if exists privado.decidir_folga(bigint, boolean, text);
drop function if exists privado.definir_jornada(uuid, time);
drop function if exists privado.admin_situacao_presenca(bigint, text, text, text);
drop function if exists privado.recalcular_compensacao(uuid, date);
drop function if exists privado.situacao_horario(integer);

drop table if exists public.folgas;
drop table if exists public.presenca_reaberturas;
