alter table public.perfis add column if not exists trocar_senha boolean not null default true;

create or replace function privado.papel_atual()
returns public.papel
language sql stable security definer set search_path = ''
as $$
  select p.papel from public.perfis p where p.id = auth.uid() and p.ativo and not p.trocar_senha;
$$;

create or replace function privado.senha_trocada()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.encrypted_password is distinct from old.encrypted_password then
    update public.perfis set trocar_senha = false where id = new.id and trocar_senha;
  end if;
  return new;
end;
$$;
revoke all on function privado.senha_trocada() from public, anon, authenticated;

drop trigger if exists fsm_senha_trocada on auth.users;
create trigger fsm_senha_trocada
  after update of encrypted_password on auth.users
  for each row execute function privado.senha_trocada();

create or replace function privado.meu_acesso()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'papel', p.papel,
    'nome', p.nome,
    'escola_id', p.escola_id,
    'carteira_id', p.carteira_id,
    'precisa_trocar_senha', p.trocar_senha,
    'precisa_mfa', p.papel in ('gerente', 'coordenador', 'analista') and not privado.mfa_ok(),
    'acesso_ok', privado.acesso_ok()
  )
  from public.perfis p
  where p.id = auth.uid() and p.ativo;
$$;
revoke all on function privado.meu_acesso() from public, anon;
grant execute on function privado.meu_acesso() to authenticated;
