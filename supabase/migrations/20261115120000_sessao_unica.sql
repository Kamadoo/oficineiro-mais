create or replace function privado.sessao_valida()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select coalesce(auth.jwt() ->> 'session_id', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
      or exists (select 1 from auth.sessions s where s.id = (auth.jwt() ->> 'session_id')::uuid);
$$;

create or replace function privado.acesso_ok()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select privado.papel_atual() is not null and privado.mfa_ok() and privado.sessao_valida();
$$;

revoke all on function privado.sessao_valida() from public, anon;
grant execute on function privado.sessao_valida() to authenticated;
