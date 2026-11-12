begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Aaa', 'Aaa - Escola A', 'CS1'), ('Bbb', 'Bbb - Escola B', 'CS1');
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000000a1', 'of.a@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000a2', 'of.s@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000c1', 'co@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000d1', 'di.a@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000d2', 'di.b@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000000a1', 'Oficineiro Mudou', 'oficineiro', (select id from public.escolas where sigla = 'Bbb'), 'of.a', false),
  ('00000000-0000-0000-0000-0000000000a2', 'Oficineiro Sem Registro', 'oficineiro', (select id from public.escolas where sigla = 'Bbb'), 'of.s', false),
  ('00000000-0000-0000-0000-0000000000c1', 'Coordenação', 'coordenador', null, 'co.x', false),
  ('00000000-0000-0000-0000-0000000000d1', 'Direção A', 'direcao', (select id from public.escolas where sigla = 'Aaa'), 'di.a', false),
  ('00000000-0000-0000-0000-0000000000d2', 'Direção B', 'direcao', (select id from public.escolas where sigla = 'Bbb'), 'di.b', false);
insert into public.presencas (oficineiro_id, escola_id, data, inicio)
  values ('00000000-0000-0000-0000-0000000000a1', (select id from public.escolas where sigla = 'Aaa'), '2026-10-20', '2026-10-20 10:00+00');

create function pg_temp.como(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;
grant execute on function pg_temp.como(text) to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000000d1');
set local role authenticated;
select is((select count(*)::int from public.perfis where id = '00000000-0000-0000-0000-0000000000a1'), 0,
          'direção antiga não vê o cadastro de quem mudou de escola');
select is((select string_agg(nome, ',') from public.nomes_da_escola()), 'Oficineiro Mudou',
          'direção antiga vê o nome de quem tem registros na escola');
select is((select count(*)::int from public.presencas), 1, 'pendências antigas continuam com a direção antiga');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000d2');
set local role authenticated;
select is((select count(*)::int from public.nomes_da_escola()), 0, 'direção da escola nova não recebe nomes sem registros nela');
select is((select count(*)::int from public.presencas), 0, 'direção da escola nova não vê as pendências da escola antiga');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
select throws_ok($$select * from public.nomes_da_escola()$$, '42501', null, 'oficineiro não usa a lista de nomes');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
set local role authenticated;
select throws_ok($$select * from public.nomes_da_escola()$$, '42501', null, 'coordenação já vê todos e não usa a lista');
reset role;

set local role anon;
select throws_ok($$select * from public.nomes_da_escola()$$, '42501', null, 'sem login não acessa');
reset role;

select * from finish();
rollback;
