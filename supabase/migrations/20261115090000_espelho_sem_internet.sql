drop function if exists privado.espelho_dias(uuid, date, date);

create or replace function privado.espelho_dias(p_oficineiro uuid, p_ini date, p_fim date)
returns table(data date, entrada timestamptz, saida_almoco timestamptz, retorno_almoco timestamptz, saida timestamptz,
              trabalhado_min integer, contabilizado_min integer, nao_contabilizado_min integer, situacao text, ajuste text,
              sem_internet jsonb)
language sql stable security definer set search_path = ''
as $$
  with d as (
    select g::date as data from generate_series(p_ini, least(p_fim, privado.hoje()), interval '1 day') g
  )
  select d.data, p.inicio, p.pausa_inicio, p.pausa_fim, p.fim,
         case when p.fim is not null then privado.trabalhado_dia(p) end,
         case when p.fim is not null then least(privado.trabalhado_dia(p), privado.limite_dia()) end,
         case when p.fim is not null then greatest(0, privado.trabalhado_dia(p) - privado.limite_dia()) end,
         case when p.id is null then 'falta'
              when p.fim is null or (p.pausa_inicio is not null and p.pausa_fim is null) then 'pendente'
              when privado.trabalhado_dia(p) > privado.limite_dia() then 'acima_8h'
              else 'regular' end,
         (select a.status from public.presenca_ajustes a
           where a.oficineiro_id = p_oficineiro and a.data = d.data order by a.pedido_em desc limit 1),
         coalesce((select jsonb_agg(jsonb_build_object('tipo', m.tipo, 'atraso_s', m.diferenca_relogio_s)
                                    order by m.registrado_em)
                     from public.presenca_marcacoes m
                    where m.presenca_id = p.id and m.sem_internet), '[]'::jsonb)
    from d
    left join public.presencas p on p.oficineiro_id = p_oficineiro and p.data = d.data
   where p.id is not null
      or (d.data < privado.hoje() and privado.oficinas_do_dia(p_oficineiro, d.data) is not null)
   order by d.data desc
$$;

revoke all on function privado.espelho_dias(uuid, date, date) from public, anon, authenticated;
