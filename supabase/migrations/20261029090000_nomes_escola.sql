create or replace function privado.nomes_da_escola()
returns table(id uuid, nome text)
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
       or exists (select 1 from public.folgas x where x.oficineiro_id = p.id and x.escola_id = v_esc)
       or exists (select 1 from public.aulas_registro x where x.oficineiro_id = p.id and x.escola_id = v_esc))
   order by p.nome;
end;
$$;
revoke all on function privado.nomes_da_escola() from public, anon;
grant execute on function privado.nomes_da_escola() to authenticated;

create or replace function public.nomes_da_escola()
returns table(id uuid, nome text)
language sql stable security invoker set search_path = ''
as $$ select n.id, n.nome from privado.nomes_da_escola() n $$;
revoke all on function public.nomes_da_escola() from public, anon;
grant execute on function public.nomes_da_escola() to authenticated;
