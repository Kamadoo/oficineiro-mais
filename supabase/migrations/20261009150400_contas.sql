create or replace function public.meu_acesso()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'papel', p.papel,
    'nome', p.nome,
    'escola_id', p.escola_id,
    'carteira_id', p.carteira_id,
    'acesso_ok', privado.acesso_ok(),
    'precisa_mfa', p.papel in ('gerente', 'coordenador', 'analista') and not privado.mfa_ok()
  )
  from public.perfis p
  where p.id = auth.uid() and p.ativo;
$$;
revoke all on function public.meu_acesso() from public, anon;
grant execute on function public.meu_acesso() to authenticated;

create or replace function public.registrar_acao_admin(p_ator uuid, p_acao text, p_registro text, p_detalhes jsonb default null)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if p_acao !~ '^[A-Z_]{3,40}$' then raise exception 'ação inválida' using errcode = '22023'; end if;
  insert into auditoria.eventos (usuario_id, papel, aal, acao, tabela, registro, detalhes)
  values (p_ator, (select papel::text from public.perfis where id = p_ator), 'aal2', p_acao, 'perfis', p_registro, p_detalhes);
end;
$$;
revoke all on function public.registrar_acao_admin(uuid, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.registrar_acao_admin(uuid, text, text, jsonb) to service_role;

do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as assinatura
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public', 'privado', 'auditoria')
       and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  loop
    execute format('revoke execute on function %s from public, anon', f.assinatura);
  end loop;
end $$;

alter default privileges for role postgres revoke execute on functions from public;
alter default privileges for role postgres in schema public    revoke execute on functions from public, anon, authenticated;
alter default privileges for role postgres in schema privado   revoke execute on functions from public, anon, authenticated;
alter default privileges for role postgres in schema auditoria revoke execute on functions from public, anon, authenticated;
alter default privileges for role postgres in schema privado   revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema auditoria revoke all on tables from anon, authenticated;
