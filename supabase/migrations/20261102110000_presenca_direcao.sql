drop policy if exists presenca_tentativas_ler on public.presenca_tentativas;
create policy presenca_tentativas_ler on public.presenca_tentativas for select to authenticated
  using (oficineiro_id = (select auth.uid())
         or ((select privado.papel_atual()) in ('direcao', 'coordenador', 'gerente') and privado.ve_escola(escola_id)));

drop policy if exists presenca_ajustes_ler on public.presenca_ajustes;
create policy presenca_ajustes_ler on public.presenca_ajustes for select to authenticated
  using (oficineiro_id = (select auth.uid())
         or ((select privado.papel_atual()) in ('direcao', 'coordenador', 'gerente') and privado.ve_escola(escola_id)));

drop policy if exists espelho_assinaturas_ler on public.espelho_assinaturas;
create policy espelho_assinaturas_ler on public.espelho_assinaturas for select to authenticated
  using (oficineiro_id = (select auth.uid())
         or (select privado.papel_atual()) in ('coordenador', 'gerente')
         or ((select privado.papel_atual()) = 'direcao'
             and exists (select 1 from public.perfis p where p.id = oficineiro_id and privado.ve_escola(p.escola_id))));

create or replace function privado.decidir_ajuste(p_id bigint, p_aprovar boolean, p_obs text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_a public.presenca_ajustes;
  v_p public.presencas;
  v_n public.presencas;
begin
  if not privado.acesso_ok() or (privado.papel_atual() is distinct from 'direcao' and not privado.eh_admin()) then
    perform privado.negar();
  end if;
  select * into v_a from public.presenca_ajustes where id = p_id for update;
  if v_a.id is null or not privado.ve_escola(v_a.escola_id) then perform privado.invalido('solicitação não encontrada'); end if;
  if v_a.status <> 'em_analise' then perform privado.invalido('esta solicitação já foi analisada'); end if;
  if not coalesce(p_aprovar, false) and length(trim(coalesce(p_obs, ''))) < 5 then
    perform privado.invalido('explique por que a solicitação foi recusada');
  end if;
  if coalesce(p_aprovar, false) and v_a.tipo <> 'falta' then
    select * into v_p from public.presencas where oficineiro_id = v_a.oficineiro_id and data = v_a.data for update;
    v_n := privado.horarios_ajustados(v_p, v_a.data, v_a.entrada, v_a.saida_almoco, v_a.retorno_almoco, v_a.saida);
    if v_p.id is null then
      insert into public.presencas (oficineiro_id, escola_id, data, inicio, pausa_inicio, pausa_fim, fim, horario_status, ponto)
      values (v_a.oficineiro_id, v_a.escola_id, v_a.data, v_n.inicio, v_n.pausa_inicio, v_n.pausa_fim, v_n.fim, 'dentro', true)
      returning * into v_n;
    else
      update public.presencas
         set inicio = v_n.inicio, pausa_inicio = v_n.pausa_inicio, pausa_fim = v_n.pausa_fim, fim = v_n.fim
       where id = v_p.id
      returning * into v_n;
    end if;
    perform privado.calcular_dia(v_n.id);
  end if;
  update public.presenca_ajustes
     set status = case when p_aprovar then 'aprovada' else 'recusada' end,
         analisado_por = auth.uid(), analisado_em = now(),
         analise_obs = nullif(left(trim(coalesce(p_obs, '')), 500), ''),
         original = case when p_aprovar and v_p.id is not null
                         then jsonb_build_object('entrada', v_p.inicio, 'saida_almoco', v_p.pausa_inicio,
                                                 'retorno_almoco', v_p.pausa_fim, 'saida', v_p.fim) end
   where id = p_id;
end;
$$;

create or replace function privado.ajustes_presenca(p_status text default null)
returns table(id bigint, oficineiro_id uuid, nome text, escola_id smallint, escola text, data date, tipo text,
              entrada time, saida_almoco time, retorno_almoco time, saida time, motivo text, status text,
              pedido_em timestamptz, analisado_em timestamptz, analise_obs text)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not privado.acesso_ok() or privado.papel_atual() not in ('oficineiro', 'direcao', 'coordenador', 'gerente') then
    perform privado.negar();
  end if;
  return query
  select a.id, a.oficineiro_id, o.nome, a.escola_id, e.nome, a.data, a.tipo, a.entrada, a.saida_almoco, a.retorno_almoco,
         a.saida, a.motivo, a.status, a.pedido_em, a.analisado_em, a.analise_obs
    from public.presenca_ajustes a
    join public.perfis o on o.id = a.oficineiro_id
    join public.escolas e on e.id = a.escola_id
   where (p_status is null or a.status = p_status)
     and case when privado.papel_atual() = 'oficineiro' then a.oficineiro_id = auth.uid() else privado.ve_escola(a.escola_id) end
   order by a.pedido_em desc
   limit 300;
end;
$$;

create or replace function privado.painel_presenca()
returns table(oficineiro_id uuid, nome text, escola_id smallint, escola text, turno text, oficina text,
              entrada timestamptz, saida_almoco timestamptz, retorno_almoco timestamptz, saida timestamptz,
              trabalhado_min integer, situacao text, escalado boolean, atualizado_em timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_agora timestamptz := now();
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if not privado.acesso_ok() or privado.papel_atual() not in ('direcao', 'coordenador', 'gerente') then perform privado.negar(); end if;
  return query
  select o.id, o.nome, e.id, e.nome, o.turno, privado.oficinas_do_dia(o.id, v_hoje),
         p.inicio, p.pausa_inicio, p.pausa_fim, p.fim,
         case when p.id is null then 0 else privado.trabalhado_dia(p, v_agora) end,
         case when p.id is null then 'sem_registro'
              when p.fim is not null then 'encerrado'
              when p.pausa_inicio is not null and p.pausa_fim is null then 'almoco'
              when privado.trabalhado_dia(p, v_agora) >= privado.limite_dia() - 30 then 'perto_limite'
              else 'trabalhando' end,
         privado.oficinas_do_dia(o.id, v_hoje) is not null,
         v_agora
    from public.perfis o
    join public.escolas e on e.id = o.escola_id
    left join lateral (
      select x.* from public.presencas x
       where x.oficineiro_id = o.id and (x.data = v_hoje or (x.fim is null and x.inicio > v_agora - interval '16 hours'))
       order by x.inicio desc limit 1
    ) p on true
   where o.papel = 'oficineiro' and o.ativo and privado.ve_escola(o.escola_id)
   order by e.nome, o.nome;
end;
$$;

create or replace function privado.espelho_oficineiro(p_oficineiro uuid, p_competencia date default null)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_comp date := coalesce(date_trunc('month', p_competencia)::date, privado.ciclo_de(privado.hoje()));
begin
  if not privado.acesso_ok() or privado.papel_atual() not in ('direcao', 'coordenador', 'gerente') then perform privado.negar(); end if;
  if not exists (select 1 from public.perfis p where p.id = p_oficineiro and p.papel = 'oficineiro' and privado.ve_escola(p.escola_id)) then
    perform privado.invalido('oficineiro não encontrado');
  end if;
  return jsonb_build_object(
    'competencia', v_comp,
    'inicio', privado.ciclo_inicio(v_comp),
    'fim', privado.ciclo_fim(v_comp),
    'assinado_em', (select a.assinado_em from public.espelho_assinaturas a where a.oficineiro_id = p_oficineiro and a.competencia = v_comp),
    'dias', coalesce((select jsonb_agg(to_jsonb(x)) from privado.espelho_dias(p_oficineiro, privado.ciclo_inicio(v_comp), privado.ciclo_fim(v_comp)) x), '[]'::jsonb));
end;
$$;

revoke all on function privado.espelho_oficineiro(uuid, date) from public, anon;
grant execute on function privado.espelho_oficineiro(uuid, date) to authenticated;

create or replace function public.espelho_oficineiro(p_oficineiro uuid, p_competencia date default null)
returns jsonb language sql stable security invoker set search_path = ''
as $$ select privado.espelho_oficineiro(p_oficineiro, p_competencia) $$;

revoke all on function public.espelho_oficineiro(uuid, date) from public, anon;
grant execute on function public.espelho_oficineiro(uuid, date) to authenticated;
