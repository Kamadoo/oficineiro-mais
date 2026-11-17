begin;
create extension if not exists pgtap with schema extensions;
select plan(20);

insert into public.carteiras values ('JS1', 'JS1 - Teste'), ('JS2', 'JS2 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values
  ('Jsa', 'Jsa - Escola Status A', 'JS1'),
  ('Jsb', 'Jsb - Escola Status B', 'JS2');
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000006a1', 'js.gerente@exemplo.test'),
  ('00000000-0000-0000-0000-0000000006a2', 'js.coord@exemplo.test'),
  ('00000000-0000-0000-0000-0000000006a3', 'js.analista@exemplo.test'),
  ('00000000-0000-0000-0000-0000000006a4', 'js.direcao@exemplo.test');
insert into public.perfis (id, nome, papel, escola_id, carteira_id, trocar_senha) values
  ('00000000-0000-0000-0000-0000000006a1', 'Gerente Status', 'gerente', null, null, false),
  ('00000000-0000-0000-0000-0000000006a2', 'Coord Status', 'coordenador', null, null, false),
  ('00000000-0000-0000-0000-0000000006a3', 'Analista Status', 'analista', null, 'JS1', false),
  ('00000000-0000-0000-0000-0000000006a4', 'Direcao Status', 'direcao', (select id from public.escolas where sigla = 'Jsa'), null, false);
insert into public.jornada_pessoas (escola_id, nome, tipo, ano_escolar, dias_sem_acesso, dias_acesso, base_ref)
values ((select id from public.escolas where sigla = 'Jsa'), 'Aluno Status', 'A', 4, 3, 10, '2026-11-11');

create function pg_temp.como(p_uid uuid, p_aal text default 'aal2') returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
$$;
create function pg_temp.esc(p_sigla text) returns smallint language sql as $$
  select id from public.escolas where sigla = p_sigla;
$$;
grant execute on function pg_temp.esc(text) to authenticated;

select ok(not has_table_privilege('authenticated', 'public.jornada_escola_status', 'INSERT'), 'status da escola sem gravação direta');
select ok(not has_table_privilege('authenticated', 'public.jornada_carteira_status', 'UPDATE'), 'status da carteira sem alteração direta');
select ok(not has_function_privilege('anon', 'public.registrar_status_escola(smallint, text, text, text, date)', 'EXECUTE'),
          'visitante não registra status');

select pg_temp.como('00000000-0000-0000-0000-0000000006a3');
set local role authenticated;
select ok(public.registrar_status_escola(pg_temp.esc('Jsa'), 'acao_planejada', 'Reunião com a direção', 'Levar lista', null) > 0,
          'analista registra status na escola da carteira');
select throws_ok($$ select public.registrar_status_escola(pg_temp.esc('Jsb'), 'em_execucao') $$, '42501', null,
                 'analista não registra status fora da carteira');
select throws_ok($$ select public.registrar_status_escola(pg_temp.esc('Jsa'), 'qualquer') $$, '22023', null, 'status inválido recusado');
select throws_ok($$ select public.registrar_status_escola(pg_temp.esc('Jsa'), 'concluida', repeat('a', 1001)) $$, '22023', null,
                 'ação longa recusada');
select ok(public.registrar_status_carteira('JS1', 'atencao', 'Duas escolas abaixo da meta') > 0, 'analista avalia a própria carteira');
select throws_ok($$ select public.registrar_status_carteira('JS2', 'critico', 'Fora da carteira') $$, '42501', null,
                 'analista não avalia outra carteira');
select throws_ok($$ select public.registrar_status_carteira('JS1', 'critico', ' ') $$, '22023', null, 'resumo vazio recusado');
select is((select count(*)::int from public.jornada_escola_status), 1, 'analista lê só o status da sua carteira');
select is((select count(*)::int from public.jornada_carteira_status), 1, 'analista lê só a avaliação da sua carteira');
reset role;

select is((select base_ref from public.jornada_escola_status limit 1), '2026-11-11'::date, 'status guarda a data da base vigente');
select is((select autor_nome from public.jornada_carteira_status limit 1), 'Analista Status', 'avaliação guarda o nome do autor');

select pg_temp.como('00000000-0000-0000-0000-0000000006a1');
set local role authenticated;
select ok(public.registrar_status_escola(pg_temp.esc('Jsb'), 'bloqueada', 'Escola em reforma') > 0, 'gerente registra em qualquer escola');
select ok(public.registrar_status_carteira('JS2', 'critico', 'Reforma em curso') > 0, 'gerente avalia qualquer carteira');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000006a2');
set local role authenticated;
select throws_ok($$ select public.registrar_status_escola(pg_temp.esc('Jsa'), 'concluida') $$, '42501', null, 'coordenador não grava status');
select is((select count(*)::int from public.jornada_escola_status), 2, 'coordenador lê todos os status');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000006a4');
set local role authenticated;
select is((select count(*)::int from public.jornada_escola_status), 0, 'direção não lê status da Jornada');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000006a3', 'aal1');
set local role authenticated;
select throws_ok($$ select public.registrar_status_escola(pg_temp.esc('Jsa'), 'concluida') $$, '42501', null, 'sem MFA não grava');
reset role;

select * from finish();
rollback;
