begin;
create extension if not exists pgtap with schema extensions;
select plan(3);

insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000005e1', 'sessao.unica@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, usuario, trocar_senha, turno) values
  ('00000000-0000-0000-0000-0000000005e1', 'Gerente Sessão', 'gerente', 'ger.sessao', false, 'integral');
insert into auth.sessions (id, user_id) values
  ('00000000-0000-0000-0000-0000000005e2', '00000000-0000-0000-0000-0000000005e1');

create function pg_temp.como(p_sessao text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000005e1', 'role', 'authenticated',
                                                            'aal', 'aal2', 'session_id', p_sessao)::text, true);
$$;
grant execute on function pg_temp.como(text) to authenticated;

set local role authenticated;
select pg_temp.como('00000000-0000-0000-0000-0000000005e2');
select is(privado.acesso_ok(), true, 'a sessão ativa tem acesso');
select pg_temp.como('00000000-0000-0000-0000-0000000005e3');
select is(privado.acesso_ok(), false, 'a sessão encerrada em outro login perde o acesso');
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000005e1', 'role', 'authenticated',
                                                          'aal', 'aal2')::text, true);
select is(privado.acesso_ok(), true, 'token sem sessão (chamadas internas) segue a regra anterior');
reset role;

select * from finish();
rollback;
