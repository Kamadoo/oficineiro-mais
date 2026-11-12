begin;
create extension if not exists pgtap with schema extensions;
select plan(6);

create or replace function privado.hoje() returns date language sql stable set search_path = ''
  as $$ select coalesce(nullif(current_setting('t.hoje', true), '')::date, (now() at time zone 'America/Sao_Paulo')::date) $$;
select set_config('t.hoje', '2026-10-20', true);

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Aaa', 'Aaa - Escola A', 'CS1');
insert into public.turmas (escola_id, ano, turma, matriculados) values ((select id from public.escolas), 3, 'A', 27), ((select id from public.escolas), 4, 'B', null);
insert into auth.users (id, email, encrypted_password) values ('00000000-0000-0000-0000-0000000000a1', 'of.a@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha)
  values ('00000000-0000-0000-0000-0000000000a1', 'Oficineiro A', 'oficineiro', (select id from public.escolas), 'of.a', false);

create function pg_temp.como(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;
grant execute on function pg_temp.como(text) to authenticated;
insert into public.presencas (oficineiro_id, escola_id, data, inicio, fim)
select '00000000-0000-0000-0000-0000000000a1', (select id from public.escolas), d::date,
       (d::date + time '07:00') at time zone 'America/Sao_Paulo', (d::date + time '12:00') at time zone 'America/Sao_Paulo'
  from unnest(array['2026-10-19', '2026-10-20']) d;

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
select throws_ok($$insert into public.grade_aulas (ano_letivo, dia_semana, inicio, fim, ano, turma, tipo, solucao) values (2026, 1, '07:00', '07:50', 3, 'A', 'R', 'Matific')$$,
                 '22023', null, 'aula nova sem matéria é recusada');
select lives_ok($$insert into public.grade_aulas (ano_letivo, dia_semana, inicio, fim, ano, turma, tipo, solucao, componente) values (2026, 1, '07:00', '07:50', 3, 'A', 'R', 'Matific', 'Matemática')$$, 'aula com matéria é aceita');
select throws_ok($$update public.grade_aulas set componente = null$$, '22023', null, 'não dá para apagar a matéria de uma aula');
select lives_ok($$insert into public.grade_aulas (ano_letivo, dia_semana, inicio, fim, ano, turma, tipo, solucao, componente) values (2026, 2, '07:00', '07:50', 4, 'B', 'R', 'Matific', 'Ciências')$$, 'outra aula');
insert into public.aulas_registro (grade_aula_id, data, inicio, fim, turma, tipo, situacao, presentes, matriculados, conteudo)
select g.id, '2026-10-19', '07:00', '07:50', 'x', 'R', 'Realizada', 20, 40, 'Frações com o Matific.' from public.grade_aulas g where g.ano = 3;
insert into public.aulas_registro (grade_aula_id, data, inicio, fim, turma, tipo, situacao, presentes, matriculados, conteudo)
select g.id, '2026-10-20', '07:00', '07:50', 'x', 'R', 'Realizada', 20, 25, 'Ciclo da água no Matific.' from public.grade_aulas g where g.ano = 4;
select is((select matriculados from public.aulas_registro r join public.grade_aulas g on g.id = r.grade_aula_id where g.ano = 3)::int, 27, 'matriculados vêm do cadastro da turma');
select is((select matriculados from public.aulas_registro r join public.grade_aulas g on g.id = r.grade_aula_id where g.ano = 4)::int, 25, 'turma sem cadastro mantém o número informado');
reset role;

select * from finish();
rollback;
