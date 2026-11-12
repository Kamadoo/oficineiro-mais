alter table public.perfis add column if not exists sem_mfa boolean not null default false;

create or replace function privado.dispensa_mfa()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.perfis p where p.id = auth.uid() and p.ativo and p.sem_mfa)
     and exists (select 1 from vault.secrets where name = 'fsm_ambiente_teste');
$$;
revoke all on function privado.dispensa_mfa() from public, anon;
grant execute on function privado.dispensa_mfa() to authenticated;

create or replace function privado.mfa_ok()
returns boolean
language sql stable set search_path = ''
as $$
  select coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2' or privado.dispensa_mfa();
$$;
