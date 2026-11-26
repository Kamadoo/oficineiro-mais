create or replace function privado.dispensa_mfa()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.perfis p where p.id = auth.uid() and p.ativo and p.sem_mfa)
     and exists (select 1 from vault.secrets where name in ('fsm_ambiente_teste', 'fsm_demonstracao'));
$$;
revoke all on function privado.dispensa_mfa() from public, anon;
grant execute on function privado.dispensa_mfa() to authenticated;
