begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

select is(privado.usuario_candidato('direcao', 'Clara Silva', 1), 'direcao.clara', 'cargo e primeiro nome');
select is(privado.usuario_candidato('direcao', 'Clara Silva', 2), 'direcao.clara.s', 'repetido: inicial do último sobrenome');
select is(privado.usuario_candidato('direcao', 'Clara Silva', 3), 'direcao.clara.s2', 'repetido de novo: número');
select is(privado.usuario_candidato('oficineiro', 'Maria José da Conceição', 1), 'oficineiro.maria', 'acentos e partículas ignorados');

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Aaa', 'Aaa - Escola A', 'CS1');
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000000e1', 'a@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000e2', 'b@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000e3', 'c@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000e4', 'd@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, escola_id) values
  ('00000000-0000-0000-0000-0000000000e1', 'Clara Silva', 'direcao', (select id from public.escolas where sigla = 'Aaa')),
  ('00000000-0000-0000-0000-0000000000e2', 'Clara Santos', 'direcao', (select id from public.escolas where sigla = 'Aaa')),
  ('00000000-0000-0000-0000-0000000000e3', 'Clara Souza', 'direcao', (select id from public.escolas where sigla = 'Aaa')),
  ('00000000-0000-0000-0000-0000000000e4', 'Clara Silva', 'oficineiro', (select id from public.escolas where sigla = 'Aaa'));

create function pg_temp.como(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;
grant execute on function pg_temp.como(text) to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000000e1');
set local role authenticated;
select is(public.gerar_meu_usuario(), 'direcao.clara', 'primeira Clara da direção');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000000e2');
set local role authenticated;
select is(public.gerar_meu_usuario(), 'direcao.clara.s', 'segunda Clara recebe a inicial do sobrenome');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000000e3');
set local role authenticated;
select is(public.gerar_meu_usuario(), 'direcao.clara.s2', 'terceira Clara com a mesma inicial recebe número');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000000e4');
set local role authenticated;
select is(public.gerar_meu_usuario(), 'oficineiro.clara', 'mesmo nome em outro cargo não conflita');
reset role;

select * from finish();
rollback;
