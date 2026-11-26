alter table privado.conta_extras add column if not exists novidade_vista integer check (novidade_vista between 1 and 1000000);

create or replace function privado.minha_novidade_vista()
returns integer
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not privado.acesso_ok() then perform privado.negar(); end if;
  return (select novidade_vista from privado.conta_extras where usuario_id = auth.uid());
end;
$$;

create or replace function privado.marcar_novidade_vista(p_novidade integer)
returns integer
language plpgsql security definer set search_path = ''
as $$
begin
  if not privado.acesso_ok() then perform privado.negar(); end if;
  if p_novidade is null or p_novidade < 1 or p_novidade > 1000000 then perform privado.invalido('novidade inválida'); end if;
  insert into privado.conta_extras as x (usuario_id, novidade_vista) values (auth.uid(), p_novidade)
  on conflict (usuario_id) do update set novidade_vista = greatest(coalesce(x.novidade_vista, 0), excluded.novidade_vista);
  return (select novidade_vista from privado.conta_extras where usuario_id = auth.uid());
end;
$$;

create or replace function public.minha_novidade_vista()
returns integer language sql stable security invoker set search_path = ''
as $$ select privado.minha_novidade_vista() $$;

create or replace function public.marcar_novidade_vista(p_novidade integer)
returns integer language sql security invoker set search_path = ''
as $$ select privado.marcar_novidade_vista(p_novidade) $$;

revoke all on function privado.minha_novidade_vista(), privado.marcar_novidade_vista(integer),
                       public.minha_novidade_vista(), public.marcar_novidade_vista(integer) from public, anon;
grant execute on function privado.minha_novidade_vista(), privado.marcar_novidade_vista(integer),
                          public.minha_novidade_vista(), public.marcar_novidade_vista(integer) to authenticated;
