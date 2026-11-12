begin;
create extension if not exists pgtap with schema extensions;
select plan(29);

create or replace function privado.hoje() returns date language sql stable set search_path = ''
  as $$ select coalesce(nullif(current_setting('t.hoje', true), '')::date, (now() at time zone 'America/Sao_Paulo')::date) $$;
select set_config('t.hoje', '2026-10-20', true);

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Aaa', 'Aaa - Escola A', 'CS1');
insert into public.turmas (escola_id, ano, turma, matriculados) values ((select id from public.escolas), -2, 'G', 18);
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000000a1', 'of.a@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000a0', 'adm@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000000a1', 'Oficineiro A', 'oficineiro', (select id from public.escolas), 'of.a', false),
  ('00000000-0000-0000-0000-0000000000a0', 'Administração', 'administrador', null, 'adm.ti', false);
insert into public.presencas (oficineiro_id, escola_id, data, inicio, fim)
values ('00000000-0000-0000-0000-0000000000a1', (select id from public.escolas), '2026-10-20',
        '2026-10-20 07:00-03', '2026-10-20 10:30-03');

create function pg_temp.como(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;
grant execute on function pg_temp.como(text) to authenticated;
create temp table ids (k text primary key, v bigint);
grant select, insert on ids to authenticated;

select is(privado.ano_rotulo(-2::smallint) || ' / ' || privado.ano_rotulo(-1::smallint) || ' / ' || privado.ano_rotulo(9::smallint),
          '1º período / 2º período / 9º ano', 'rótulos de ano incluem educação infantil e anos finais');
select is(privado.oficina_categoria('Robótica') || ' / ' || privado.oficina_categoria('Programa Construtores – Minecraft') || ' / ' || privado.oficina_categoria('Capoeira'),
          'Tecnologia / Tecnologia / Outras', 'categoria interna das oficinas');
select is(array_length(privado.oficinas(), 1), 28, 'lista de oficinas completa');
select ok('Língua Inglesa' = any (privado.componentes()) and not ('Outro' = any (privado.componentes())), 'componentes curriculares atualizados');

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
select throws_ok($$insert into public.grade_aulas (dia_semana, horario, inicio, fim, ano, turma, tipo, solucao, componente)
                   values (1, 1, '06:50', '07:40', 3, 'A', 'R', 'Matific', 'Matemática')$$, '22023', 'As atividades começam a partir das 07:00', 'antes das 07:00 é recusado');
select throws_ok($$insert into public.grade_aulas (dia_semana, horario, inicio, fim, ano, turma, tipo, solucao, componente)
                   values (1, 11, '15:30', '17:10', 3, 'A', 'R', 'Matific', 'Matemática')$$, '22023', 'A atividade precisa terminar até as 17:00', 'término depois das 17:00 é recusado');
select throws_ok($$insert into public.grade_aulas (dia_semana, horario, inicio, fim, ano, turma, tipo, solucao, componente)
                   values (1, 1, '07:00', '07:40', 3, 'A', 'R', 'Matific', 'Matemática')$$, '22023', null, 'horário precisa ter 50 minutos');
select throws_ok($$insert into public.grade_aulas (dia_semana, horario, inicio, fim, ano, turma, tipo, solucao, componente)
                   values (1, 13, '07:00', '07:50', 3, 'A', 'R', 'Matific', 'Matemática')$$, '23514', null, 'só existem do 1º ao 12º horário');
select lives_ok($$with x as (insert into public.grade_aulas (dia_semana, horario, inicio, fim, ano, turma, tipo, solucao, componente)
                   values (2, 3, '09:00', '09:50', -2, 'G', 'R', 'MS Reflect', 'Língua Inglesa') returning id) insert into ids select 'regular', id from x$$,
                'aula regular com hora livre, 1º período e turma G');
select throws_ok($$insert into public.grade_aulas (dia_semana, horario, inicio, fim, ano, turma, tipo, solucao, componente)
                   values (2, 4, '09:30', '10:20', 5, 'A', 'R', 'Canva', 'Arte')$$, '22023', null, 'sobreposição no mesmo dia é recusada');
select throws_ok($$insert into public.grade_aulas (dia_semana, horario, inicio, fim, ano, turma, tipo, solucao)
                   values (3, 1, '07:00', '07:50', 5, 'A', 'R', 'Canva')$$, '22023', 'escolha o componente curricular', 'aula regular exige componente');
select throws_ok($$insert into public.grade_aulas (dia_semana, horario, inicio, fim, ano, turma, tipo)
                   values (3, 1, '07:00', '07:50', 5, 'A', 'P')$$, '22023', 'escolha a oficina', 'tempo integral exige oficina');
select lives_ok($$with x as (insert into public.grade_aulas (dia_semana, horario, inicio, fim, ano, turma, tipo, oficina, solucao, componente)
                   values (3, 2, '07:50', '09:30', 6, 'H', 'P', 'Capoeira', 'Matific', 'Arte') returning id) insert into ids select 'integral', id from x$$,
                'tempo integral com oficina digitada em Outro');
select is((select coalesce(solucao, '-') || ' ' || coalesce(componente, '-') || ' ' || oficina from public.grade_aulas where id = (select v from ids where k = 'integral')),
          '- - Capoeira', 'no tempo integral, solução e componente não são gravados');
select lives_ok($$with x as (insert into public.grade_aulas (dia_semana, horario, inicio, fim, ano, turma, tipo, solucao, componente)
                   values (2, 5, '10:40', '11:30', 4, 'B', 'F', 'Canva', 'Arte') returning id) insert into ids select 'formacao', id from x$$,
                'formação de professores sem ano, turma e componente');
select is((select coalesce(ano::text, '-') || coalesce(turma, '-') || coalesce(componente, '-') from public.grade_aulas where id = (select v from ids where k = 'formacao')),
          '---', 'formação não guarda ano, turma nem componente');
select throws_ok($$insert into public.grade_aulas (dia_semana, horario, inicio, fim, tipo)
                   values (4, 1, '07:00', '07:50', 'F')$$, '22023', 'escolha a solução prevista', 'formação exige a solução');

select throws_ok($$select public.salvar_semana_grade('2026-10-26', jsonb_build_array(jsonb_build_object('grade_aula_id', (select v from ids where k = 'regular'), 'tipo', 'F', 'solucao', 'Canva')))$$,
  '22023', null, 'aula de turma não vira formação só numa semana');
select is(public.salvar_semana_grade('2026-10-26', jsonb_build_array(
  jsonb_build_object('grade_aula_id', (select v from ids where k = 'regular'), 'tipo', 'P', 'oficina', 'Robótica', 'solucao', 'Matific'))), 1, 'troca para tempo integral numa semana');
select is((select tipo || ' ' || oficina || ' ' || coalesce(solucao, '-') || ' ' || coalesce(componente, '-') from public.grade_semanas),
          'P Robótica - -', 'semana guarda a oficina e limpa os campos do outro tipo');

select lives_ok($$insert into public.aulas_registro (grade_aula_id, data, inicio, fim, turma, tipo, situacao, solucao, componente, presentes, conteudo, objetivo)
                  values ((select v from ids where k = 'regular'), '2026-10-20', '00:00', '00:50', 'x', 'R', 'Realizada', 'MS Reflect', 'Língua Inglesa', 15, 'Apresentação em inglês.', 'Sim')$$,
                'registra atividade dentro da presença');
select is((select turma || ' · ' || horario || 'º horário' from public.aulas_registro where grade_aula_id = (select v from ids where k = 'regular')),
          '1º período · Turma G · 3º horário', 'turma e horário do registro vêm da grade');
select is((select matriculados::int from public.aulas_registro where grade_aula_id = (select v from ids where k = 'regular')), 18, 'matriculados da turma do 1º período');
select throws_ok($$insert into public.aulas_registro (grade_aula_id, data, inicio, fim, turma, tipo, situacao, solucao, presentes, conteudo)
                   values ((select v from ids where k = 'formacao'), '2026-10-20', '00:00', '00:50', 'x', 'F', 'Realizada', 'Canva', 8, 'Formação em Canva.')$$,
                 '22023', null, 'atividade fora da presença não é registrada como realizada');
select lives_ok($$insert into public.aulas_registro (grade_aula_id, data, inicio, fim, turma, tipo, situacao, motivo)
                  values ((select v from ids where k = 'formacao'), '2026-10-20', '00:00', '00:50', 'x', 'F', 'Não realizada', 'Ausência do professor')$$,
                'não realizada pode ser registrada sem presença');
select is((select turma from public.aulas_registro where grade_aula_id = (select v from ids where k = 'formacao')), 'Professores', 'formação aparece como Professores');
select throws_ok($$update public.aulas_registro set objetivo = 'Parcialmente' where grade_aula_id = (select v from ids where k = 'regular')$$,
                 '23514', null, 'objetivo atingido aceita só Sim ou Não');
select lives_ok($$update public.aulas_registro set conteudo = 'Apresentação em inglês com vocabulário novo.' where grade_aula_id = (select v from ids where k = 'regular')$$,
                'editar o texto de um registro realizado continua permitido');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a0');
set local role authenticated;
select lives_ok($$select public.admin_salvar_turma((select id from public.escolas), -1::smallint, 'H', 20::smallint)$$, 'administrador cadastra turma do 2º período');
reset role;

select * from finish();
rollback;
