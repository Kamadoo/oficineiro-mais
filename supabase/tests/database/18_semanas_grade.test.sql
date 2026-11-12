begin;
create extension if not exists pgtap with schema extensions;
select plan(23);

create or replace function privado.hoje() returns date language sql stable set search_path = ''
  as $$ select coalesce(nullif(current_setting('t.hoje', true), '')::date, (now() at time zone 'America/Sao_Paulo')::date) $$;
select set_config('t.hoje', '2026-10-14', true);

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Aaa', 'Aaa - Escola A', 'CS1'), ('Bbb', 'Bbb - Escola B', 'CS1');
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000000a1', 'of.a@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000b1', 'of.b@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000c1', 'co@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000d1', 'di@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000d2', 'di.a@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000000a1', 'Oficineiro A', 'oficineiro', (select id from public.escolas where sigla = 'Aaa'), 'of.a', false),
  ('00000000-0000-0000-0000-0000000000b1', 'Oficineiro B', 'oficineiro', (select id from public.escolas where sigla = 'Bbb'), 'of.b', false),
  ('00000000-0000-0000-0000-0000000000c1', 'Coordenação', 'coordenador', null, 'co.x', false),
  ('00000000-0000-0000-0000-0000000000d1', 'Direção B', 'direcao', (select id from public.escolas where sigla = 'Bbb'), 'di.b', false),
  ('00000000-0000-0000-0000-0000000000d2', 'Direção A', 'direcao', (select id from public.escolas where sigla = 'Aaa'), 'di.a', false);

create function pg_temp.como(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;
grant execute on function pg_temp.como(text) to authenticated;
create temp table ids (k text primary key, v bigint);
grant select, insert on ids to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
with x as (insert into public.grade_aulas (dia_semana, inicio, fim, ano, turma, tipo, solucao, componente)
  values (1, '07:50', '08:40', 3, 'B', 'R', 'Matific', 'Matemática') returning id) insert into ids select 'seg', id from x;
with x as (insert into public.grade_aulas (dia_semana, inicio, fim, ano, turma, tipo, solucao, componente)
  values (2, '07:50', '08:40', 4, 'A', 'R', 'Árvore', 'Língua Portuguesa') returning id) insert into ids select 'ter', id from x;
select throws_ok($$insert into public.grade_aulas (dia_semana, inicio, fim, ano, turma, tipo, solucao, componente) values (3, '07:00', '07:50', 3, 'B', 'R', 'Matific', 'Química')$$,
  '23514', null, 'matéria fora da lista é recusada');
select is((select componente from public.grade_aulas where id = (select v from ids where k = 'seg')), 'Matemática', 'matéria gravada na grade');
select lives_ok($$select public.enviar_grade(2026::smallint)$$, 'grade enviada');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000000d2');
set local role authenticated;
select lives_ok($$select public.validar_grade('00000000-0000-0000-0000-0000000000a1', 2026::smallint, true)$$, 'direção da escola valida');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
select throws_ok($$select public.salvar_semana_grade('2026-10-20', '[]')$$, '22023', null, 'semana precisa começar na segunda');
select throws_ok($$select public.salvar_semana_grade('2026-10-05', '[]')$$, '22023', null, 'semana passada não muda');
select is(public.salvar_semana_grade('2026-10-19', jsonb_build_array(
  jsonb_build_object('grade_aula_id', (select v from ids where k = 'seg'), 'tipo', 'P', 'oficina', 'Programa Construtores – Minecraft'),
  jsonb_build_object('grade_aula_id', (select v from ids where k = 'ter'), 'tipo', 'R', 'solucao', 'Árvore'))), 1, 'só o que difere da grade padrão é gravado');
select is((select status from public.grade_envios), 'alterada', 'personalizar uma semana pede nova validação');
select is((select tipo || ' ' || oficina || ' ' || coalesce(solucao, 'sem solução') from public.grade_semanas where semana = '2026-10-19'), 'P Programa Construtores – Minecraft sem solução', 'semana personalizada gravada');
select is(public.copiar_semana_grade('2026-10-19', array['2026-11-02', '2026-11-16']::date[]), 2, 'copia para outras semanas');
select is((select count(*)::int from public.grade_semanas), 3, 'rodízio gravado nas semanas escolhidas');
select is(public.salvar_semana_grade('2026-11-02', '[]'), 0, 'semana volta para a grade padrão');
select is((select count(*)::int from public.grade_semanas where semana = '2026-11-02'), 0, 'personalização removida');
select is(public.salvar_semana_grade('2026-11-09', jsonb_build_array(
  jsonb_build_object('grade_aula_id', (select v from ids where k = 'ter'), 'tipo', 'R', 'solucao', 'Árvore', 'componente', 'Ciências'))), 1, 'trocar só a matéria numa semana também é gravado');
select is((select componente from public.grade_semanas where semana = '2026-11-09'), 'Ciências', 'matéria da semana gravada');
select throws_ok($$select public.salvar_semana_grade('2026-11-16', jsonb_build_array(jsonb_build_object('grade_aula_id', (select v from ids where k = 'ter'), 'tipo', 'R', 'solucao', 'Árvore', 'componente', 'Química')))$$,
  '22023', null, 'matéria fora da lista é recusada na semana');
select throws_ok($$insert into public.grade_semanas (grade_aula_id, oficineiro_id, escola_id, ano_letivo, semana, tipo, solucao)
  values ((select v from ids where k = 'seg'), auth.uid(), 1, 2026, '2026-11-09', 'P', 'X')$$, '42501', null, 'não grava direto na tabela');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
set local role authenticated;
select throws_ok($$select public.salvar_semana_grade('2026-10-26', jsonb_build_array(jsonb_build_object('grade_aula_id', (select v from ids where k = 'seg'), 'tipo', 'P', 'solucao', 'X')))$$,
  '22023', null, 'não personaliza a grade de outro oficineiro');
select is((select count(*)::int from public.grade_semanas), 0, 'outro oficineiro não vê as semanas');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000d1');
set local role authenticated;
select is((select count(*)::int from public.grade_semanas), 0, 'direção de outra escola não vê');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
set local role authenticated;
select is((select count(*)::int from public.grade_semanas), 3, 'coordenador vê as semanas personalizadas');
reset role;

select set_config('t.hoje', '2026-10-20', true);
insert into public.presencas (oficineiro_id, escola_id, data, inicio, fim)
select '00000000-0000-0000-0000-0000000000a1', (select id from public.escolas where sigla = 'Aaa'), d::date,
       (d::date + time '07:00') at time zone 'America/Sao_Paulo', (d::date + time '12:00') at time zone 'America/Sao_Paulo'
  from unnest(array['2026-10-19', '2026-10-20']) d;
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
insert into public.aulas_registro (grade_aula_id, data, inicio, fim, turma, tipo, situacao, solucao, presentes, conteudo)
values ((select v from ids where k = 'seg'), '2026-10-19', '07:50', '08:40', 'x', 'R', 'Realizada', 'Programa Construtores - Minecraft', 20, 'Aula de teste da semana.');
select is((select tipo || ' ' || oficina from public.aulas_registro), 'P Programa Construtores – Minecraft', 'registro da semana personalizada usa o tipo e a oficina da semana');
insert into public.aulas_registro (grade_aula_id, data, inicio, fim, turma, tipo, situacao, solucao, presentes, conteudo)
values ((select v from ids where k = 'ter'), '2026-10-20', '07:50', '08:40', 'x', 'C', 'Realizada', 'Árvore', 20, 'Aula de teste da semana.');
select is((select tipo from public.aulas_registro where data = '2026-10-20'), 'R', 'aula sem personalização usa a grade padrão');
reset role;

select * from finish();
rollback;
