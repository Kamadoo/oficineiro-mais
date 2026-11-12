begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Aaa', 'Aaa - Escola Teste', 'CS1');
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000000e1', 'visual@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000e2', 'normal@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, usuario, trocar_senha, sem_mfa) values
  ('00000000-0000-0000-0000-0000000000e1', 'Gerente Visual', 'gerente', 'gerente.visual', false, true),
  ('00000000-0000-0000-0000-0000000000e2', 'Gerente Normal', 'gerente', 'gerente.normal', false, false);
delete from vault.secrets where name = 'fsm_ambiente_teste';

create function pg_temp.como(p_uid text, p_aal text default 'aal2') returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
$$;
grant execute on function pg_temp.como(text, text) to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000000e1', 'aal1');
set local role authenticated;
select is((select count(*)::int from public.escolas), 0, 'fora do projeto de teste, a marcação não dispensa o autenticador');
select is((public.meu_acesso() ->> 'precisa_mfa')::boolean, true, 'fora do projeto de teste, o site pede o autenticador');
reset role;

select vault.create_secret('sim', 'fsm_ambiente_teste', 'teste');

select pg_temp.como('00000000-0000-0000-0000-0000000000e1', 'aal1');
set local role authenticated;
select is((select count(*)::int from public.escolas), 1, 'no projeto de teste, a conta marcada entra sem o autenticador');
select is((public.meu_acesso() ->> 'precisa_mfa')::boolean, false, 'o site não pede o autenticador para a conta marcada');
select throws_ok($$select sem_mfa from public.perfis$$, '42501', null, 'ninguém lê a marcação pela API');
select throws_ok($$update public.perfis set sem_mfa = true$$, '42501', null, 'ninguém liga a marcação pela API');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000e2', 'aal1');
set local role authenticated;
select is((select count(*)::int from public.escolas), 0, 'conta sem a marcação continua exigindo o autenticador');
select is((public.meu_acesso() ->> 'precisa_mfa')::boolean, true, 'o site continua pedindo o autenticador às outras contas');
reset role;

update public.perfis set ativo = false where id = '00000000-0000-0000-0000-0000000000e1';
select pg_temp.como('00000000-0000-0000-0000-0000000000e1', 'aal1');
set local role authenticated;
select is((select count(*)::int from public.escolas), 0, 'conta marcada desativada não entra');
reset role;

select * from finish();
rollback;
