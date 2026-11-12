begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Aaa', 'Aaa - Escola A', 'CS1');
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000000a1', 'of.a@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000c1', 'co@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000d1', 'di@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000d2', 'di.b@exemplo.test', 'hash');
insert into public.escolas (sigla, nome, carteira_id) values ('Bbb', 'Bbb - Escola B', 'CS1');
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000000a1', 'Oficineiro A', 'oficineiro', (select id from public.escolas where sigla = 'Aaa'), 'of.a', false),
  ('00000000-0000-0000-0000-0000000000c1', 'Coordenação', 'coordenador', null, 'co.x', false),
  ('00000000-0000-0000-0000-0000000000d1', 'Direção A', 'direcao', (select id from public.escolas where sigla = 'Aaa'), 'di.a', false),
  ('00000000-0000-0000-0000-0000000000d2', 'Direção B', 'direcao', (select id from public.escolas where sigla = 'Bbb'), 'di.b', false);

create function pg_temp.como(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;
grant execute on function pg_temp.como(text) to authenticated;
create temp table ano as select extract(year from privado.hoje())::smallint as a;
grant select on ano to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
select throws_ok($$select public.enviar_grade((select a from ano))$$, '22023', null, 'não envia grade vazia');
insert into public.grade_aulas (dia_semana, inicio, fim, ano, turma, tipo, solucao, componente) values (1, '07:00', '07:50', 3, 'A', 'R', 'Matific', 'Matemática');
select lives_ok($$select public.enviar_grade((select a from ano))$$, 'envia a grade para validação');
select throws_ok($$select public.enviar_grade((select a from ano))$$, '22023', null, 'não envia de novo enquanto aguarda');
select throws_ok($$insert into public.grade_envios (oficineiro_id, escola_id, ano_letivo, status) select auth.uid(), id, 2026, 'validada' from public.escolas$$, '42501', null, 'não se autovalida pela tabela');
select throws_ok($$select public.validar_grade(auth.uid(), (select a from ano), true)$$, '42501', null, 'oficineiro não valida a própria grade');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
set local role authenticated;
select throws_ok($$select public.validar_grade('00000000-0000-0000-0000-0000000000a1', (select a from ano), true)$$, '42501', null, 'coordenação só acompanha, não valida');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000000d2');
set local role authenticated;
select throws_ok($$select public.validar_grade('00000000-0000-0000-0000-0000000000a1', (select a from ano), true)$$, '42501', null, 'direção de outra escola não valida');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000000d1');
set local role authenticated;
select throws_ok($$select public.validar_grade('00000000-0000-0000-0000-0000000000a1', (select a from ano), false, '')$$, '22023', null, 'devolver exige comentário');
select lives_ok($$select public.validar_grade('00000000-0000-0000-0000-0000000000a1', (select a from ano), false, 'Faltou a turma do 5º ano.')$$, 'direção devolve com comentário');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
select is((select status || ' | ' || comentario from public.grade_envios), 'devolvida | Faltou a turma do 5º ano.', 'oficineiro vê a devolução e o comentário');
select lives_ok($$select public.enviar_grade((select a from ano))$$, 'reenvia depois de ajustar');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000d1');
set local role authenticated;
select lives_ok($$select public.validar_grade('00000000-0000-0000-0000-0000000000a1', (select a from ano), true)$$, 'direção da escola valida');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
update public.grade_aulas set turma = 'B';
select is((select status from public.grade_envios), 'alterada', 'mexer na grade validada pede novo envio');
select lives_ok($$select public.enviar_grade((select a from ano))$$, 'envia a grade alterada');
reset role;

select * from finish();
rollback;
