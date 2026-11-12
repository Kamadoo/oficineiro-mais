begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values
  ('Aaa', 'Aaa - Escola A', 'CS1'),
  ('Bbb', 'Bbb - Escola B', 'CS1');
insert into public.turmas (escola_id, ano, turma)
select e.id, x.ano, x.turma from (values ('Aaa', 3, 'A'), ('Aaa', 4, ''), ('Bbb', 5, 'B')) x(sig, ano, turma)
  join public.escolas e on e.sigla = x.sig;
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000000a1', 'of.a@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000b1', 'of.b@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000c1', 'co@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha)
select x.id::uuid, x.nome, x.papel::public.papel, e.id, x.usuario, false
  from (values ('00000000-0000-0000-0000-0000000000a1', 'Oficineiro A', 'oficineiro', 'of.a', 'Aaa'),
               ('00000000-0000-0000-0000-0000000000b1', 'Oficineiro B', 'oficineiro', 'of.b', 'Bbb'),
               ('00000000-0000-0000-0000-0000000000c1', 'Coordenação', 'coordenador', 'co.x', null)) x(id, nome, papel, usuario, sig)
  left join public.escolas e on e.sigla = x.sig;

create function pg_temp.como(p_uid text, p_aal text default 'aal2') returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
$$;
grant execute on function pg_temp.como(text, text) to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
select lives_ok($$insert into public.grade_aulas (dia_semana, inicio, fim, ano, turma, tipo, oficina)
                  values (3, '08:00', '08:50', 3, 'A', 'P', 'Programa Construtores – Minecraft')$$,
                'o oficineiro cria uma aula na grade (dia da semana e horário)');
select is((select e.sigla || ' ' || g.ano_letivo from public.grade_aulas g join public.escolas e on e.id = g.escola_id),
          'Aaa ' || extract(year from privado.hoje()), 'a aula fica na escola do oficineiro, no ano letivo atual');
select lives_ok($$insert into public.grade_aulas (dia_semana, inicio, fim, ano, turma, tipo, solucao, professor, componente)
                  values (4, '08:00', '08:50', 4, 'B', 'R', 'Matific', 'Prof. Teste', 'Matemática')$$,
                'mesmo horário em outro dia da semana é aceito');
select throws_ok($$insert into public.grade_aulas (dia_semana, inicio, fim, ano, turma, tipo, solucao, componente) values (3, '08:20', '09:10', 5, 'C', 'R', 'Matific', 'Matemática')$$,
                 '22023', null, 'aula que cai em cima de outra no mesmo dia é recusada');
select throws_ok($$insert into public.grade_aulas (dia_semana, inicio, fim, ano, turma, tipo, solucao, componente) values (6, '08:00', '08:50', 3, 'A', 'R', 'Matific', 'Matemática')$$,
                 '23514', null, 'só de segunda a sexta');
select throws_ok($$insert into public.grade_aulas (ano_letivo, dia_semana, inicio, fim, ano, turma, tipo, solucao, componente)
                   values (2025, 1, '08:00', '08:50', 3, 'A', 'R', 'Matific', 'Matemática')$$,
                 '42501', null, 'não mexe na grade de anos letivos passados');
select throws_ok($$insert into public.grade_aulas (escola_id, dia_semana, inicio, fim, ano, turma, tipo, solucao, componente)
                   select id, 5, '08:00', '08:50', 3, 'A', 'R', 'Matific', 'Matemática' from public.escolas where sigla = 'Bbb'$$,
                 '42501', null, 'não escolhe outra escola');
select throws_ok($$insert into public.grade_aulas (oficineiro_id, dia_semana, inicio, fim, ano, turma, tipo, solucao, componente)
                   values ('00000000-0000-0000-0000-0000000000b1', 5, '08:00', '08:50', 3, 'A', 'R', 'Matific', 'Matemática')$$,
                 '42501', null, 'não cria aula em nome de outra pessoa');
select lives_ok($$update public.grade_aulas set turma = 'D' where ano = 3$$, 'edita a própria aula ao longo do ano');
select is((select array_agg(ano || turma order by ano) from public.turmas), array['3A', '4'], 'vê só as turmas da própria escola');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
set local role authenticated;
select is((select count(*)::int from public.grade_aulas), 0, 'outro oficineiro não vê a grade de ninguém');
delete from public.grade_aulas;
update public.grade_aulas set turma = 'Z';
select is((select array_agg(ano || turma order by ano) from public.turmas), array['5B'], 'cada escola vê as próprias turmas');
reset role;

select is((select count(*)::int from public.grade_aulas where turma <> 'Z'), 2, 'outro oficineiro não apaga nem altera a grade de ninguém');

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
set local role authenticated;
select is((select count(*)::int from public.grade_aulas), 2, 'o coordenador vê a grade dos oficineiros');
delete from public.grade_aulas;
select is((select count(*)::int from public.grade_aulas), 2, 'mas não apaga nem altera');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
delete from public.grade_aulas where ano = 3;
select is((select count(*)::int from public.grade_aulas), 1, 'o oficineiro exclui a própria aula');
reset role;

set local role anon;
select throws_ok($$select 1 from public.grade_aulas$$, '42501', null, 'sem login não lê a grade');
reset role;

select * from finish();
rollback;
