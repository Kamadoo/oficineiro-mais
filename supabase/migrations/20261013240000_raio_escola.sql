create or replace function privado.definir_raio_escola(p_escola smallint, p_raio smallint)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if privado.papel_atual() is distinct from 'coordenador' or not privado.acesso_ok() then perform privado.negar(); end if;
  if p_raio is null or p_raio < 20 or p_raio > 500 then perform privado.invalido('o raio precisa ficar entre 20 e 500 metros'); end if;
  update public.escolas set raio_m = p_raio where id = p_escola;
  if not found then perform privado.invalido('escola não encontrada'); end if;
end;
$$;

create or replace function public.definir_raio_escola(p_escola smallint, p_raio smallint)
returns void language sql security invoker set search_path = ''
as $$ select privado.definir_raio_escola(p_escola, p_raio) $$;

revoke all on function privado.definir_raio_escola(smallint, smallint), public.definir_raio_escola(smallint, smallint) from public, anon;
grant execute on function privado.definir_raio_escola(smallint, smallint), public.definir_raio_escola(smallint, smallint) to authenticated;
