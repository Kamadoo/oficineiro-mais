create or replace function privado.novo_codigo_verificacao()
returns text
language sql volatile set search_path = ''
as $$
  select string_agg(
           case when i in (5, 9) then '-' else '' end ||
           substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', (get_byte(b, i - 1) % 32) + 1, 1), '' order by i)
    from (select extensions.gen_random_bytes(12) as b) x, generate_series(1, 12) i;
$$;

alter table public.relatorios_mensais add column if not exists codigo_verificacao text;
update public.relatorios_mensais set codigo_verificacao = privado.novo_codigo_verificacao() where codigo_verificacao is null;
alter table public.relatorios_mensais alter column codigo_verificacao set default privado.novo_codigo_verificacao();
alter table public.relatorios_mensais alter column codigo_verificacao set not null;
create unique index if not exists relatorios_mensais_codigo_verificacao on public.relatorios_mensais (codigo_verificacao);

create or replace function public.verificar_documento(p_codigo text)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_limpo text := upper(regexp_replace(coalesce(p_codigo, ''), '[^A-Za-z0-9]', '', 'g'));
  v_r record;
begin
  if length(v_limpo) <> 12 then
    return jsonb_build_object('encontrado', false);
  end if;
  select r.competencia, r.status, r.fechado_em, r.direcao_em, r.coordenacao_em, e.nome as escola,
         split_part(p.nome, ' ', 1) ||
           case when strpos(trim(p.nome), ' ') > 0
                then ' ' || left(regexp_replace(trim(p.nome), '^.*\s', ''), 1) || '.' else '' end as pessoa
    into v_r
    from public.relatorios_mensais r
    join public.perfis p on p.id = r.oficineiro_id
    join public.escolas e on e.id = r.escola_id
   where r.codigo_verificacao = substr(v_limpo, 1, 4) || '-' || substr(v_limpo, 5, 4) || '-' || substr(v_limpo, 9, 4);
  if not found then
    return jsonb_build_object('encontrado', false);
  end if;
  return jsonb_build_object(
    'encontrado', true,
    'competencia', v_r.competencia,
    'status', v_r.status,
    'fechado_em', v_r.fechado_em,
    'direcao_em', v_r.direcao_em,
    'coordenacao_em', v_r.coordenacao_em,
    'escola', v_r.escola,
    'pessoa', v_r.pessoa);
end;
$$;

revoke all on function privado.novo_codigo_verificacao(), public.verificar_documento(text) from public, anon, authenticated;
grant execute on function public.verificar_documento(text) to anon, authenticated;
