create or replace function privado.nome_partes(p_nome text)
returns text[]
language sql immutable set search_path = ''
as $$
  select array(
    select x
      from unnest(regexp_split_to_array(
             regexp_replace(lower(translate(coalesce(p_nome, ''), 'ÁÀÂÃÄáàâãäÉÈÊËéèêëÍÌÎÏíìîïÓÒÔÕÖóòôõöÚÙÛÜúùûüÇçÑñ',
                                                             'aaaaaaaaaaeeeeeeeeiiiiiiiioooooooooouuuuuuuuccnn')),
                            '[^a-z ]', '', 'g'), '\s+')) x
     where x <> '' and x not in ('da', 'de', 'do', 'das', 'dos', 'e'));
$$;

create or replace function privado.usuario_candidato(p_papel text, p_nome text, p_n integer)
returns text
language sql immutable set search_path = ''
as $$
  select left(p_papel || '.' || coalesce(left(p[1], 16), 'usuario')
              || case when p_n >= 2 and cardinality(p) > 1 then '.' || left(p[cardinality(p)], 1) else '' end
              || case when p_n >= 3 then (p_n - 1)::text when p_n = 2 and cardinality(p) <= 1 then '2' else '' end, 30)
    from (select privado.nome_partes(p_nome) as p) x;
$$;

create or replace function privado.gerar_meu_usuario()
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_p public.perfis;
  v_u text;
  n integer := 1;
begin
  select * into v_p from public.perfis where id = auth.uid() and ativo for update;
  if v_p.id is null or not privado.mfa_ok() then perform privado.negar(); end if;
  if v_p.usuario is not null then return v_p.usuario; end if;
  loop
    v_u := privado.usuario_candidato(v_p.papel::text, v_p.nome, n);
    if not exists (select 1 from public.perfis where usuario = v_u) then
      begin
        update public.perfis set usuario = v_u where id = v_p.id;
        return v_u;
      exception when unique_violation then
        null;
      end;
    end if;
    n := n + 1;
  end loop;
end;
$$;

drop function if exists privado.usuario_base(text);
revoke all on function privado.nome_partes(text), privado.usuario_candidato(text, text, integer) from public, anon, authenticated;
revoke all on function privado.gerar_meu_usuario() from public, anon;
grant execute on function privado.gerar_meu_usuario() to authenticated;

create or replace function public.gerar_meu_usuario()
returns text language sql security invoker set search_path = ''
as $$ select privado.gerar_meu_usuario() $$;

revoke all on function public.gerar_meu_usuario() from public, anon;
grant execute on function public.gerar_meu_usuario() to authenticated;

drop function if exists public.definir_usuario(text);
drop function if exists privado.definir_usuario(text);
