create or replace function public.jornada_resumo_mensal()
returns table (base_ref date, escola_id smallint, tipo char(1), ano_escolar smallint, n integer, nv integer, sr integer, en integer)
language sql stable security invoker set search_path = ''
as $$
  with ultima as (select max(r.base_ref) as d from public.jornada_retratos r),
       meses as (
         select max(r.base_ref) as d
           from public.jornada_retratos r, ultima u
          where r.base_ref > (u.d - interval '12 months')::date
          group by date_trunc('month', r.base_ref)
       ),
       pessoas as (
         select j.base_ref, j.escola_id, j.tipo, j.ano_escolar, j.dias_sem_acesso,
                coalesce(j.dias_acesso, 0) as dias,
                j.primeiro_acesso,
                extract(day from j.base_ref)::int as dia,
                extract(day from (date_trunc('month', j.base_ref) + interval '1 month - 1 day'))::int as dias_do_mes,
                greatest(coalesce(j.primeiro_acesso, j.base_ref - 182), j.base_ref - 182) as desde
           from public.jornada_pessoas j
          where j.base_ref in (select d from meses)
       ),
       medidas as (
         select p.*,
                p.dias_sem_acesso >= 0 and p.dias_sem_acesso < p.dia as no_mes,
                case
                  when p.dias_sem_acesso < 0 or p.dias_sem_acesso >= p.dia or p.dias = 0 then 0
                  when p.primeiro_acesso >= date_trunc('month', p.base_ref)::date then p.dias
                  else greatest(1, least(p.dias, round(p.dias::numeric
                         / least(26, greatest(1, (p.base_ref - p.desde) / 7.0)) * p.dia / 7.0)::int))
                end as usos,
                ceil(case p.tipo when 'A' then 1 else 3 end * 4 * least(1, p.dia::numeric / p.dias_do_mes) - 0.000000001)::int as meta
           from pessoas p
       )
  select m.base_ref, m.escola_id, m.tipo, m.ano_escolar,
         count(*)::int,
         count(*) filter (where m.dias_sem_acesso < 0)::int,
         count(*) filter (where m.dias_sem_acesso >= 0 and not m.no_mes)::int,
         count(*) filter (where m.no_mes and m.dias > 0 and m.usos >= m.meta)::int
    from medidas m
   group by m.base_ref, m.escola_id, m.tipo, m.ano_escolar
   order by m.base_ref, m.escola_id, m.tipo, m.ano_escolar;
$$;

revoke all on function public.jornada_resumo_mensal() from public, anon, authenticated;
grant execute on function public.jornada_resumo_mensal() to authenticated;
