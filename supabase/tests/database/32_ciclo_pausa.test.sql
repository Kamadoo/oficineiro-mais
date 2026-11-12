begin;
create extension if not exists pgtap with schema extensions;
select plan(22);

create or replace function privado.hoje() returns date language sql stable set search_path = ''
  as $$ select coalesce(nullif(current_setting('t.hoje', true), '')::date, (now() at time zone 'America/Sao_Paulo')::date) $$;

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Aaa', 'Aaa - Escola A', 'CS1');
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000000a1', 'of.a@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000c1', 'co@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000a0', 'adm@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000000a1', 'Oficineiro A', 'oficineiro', (select id from public.escolas), 'of.a', false),
  ('00000000-0000-0000-0000-0000000000c1', 'Coordenação', 'coordenador', null, 'co.x', false),
  ('00000000-0000-0000-0000-0000000000a0', 'Administração', 'administrador', null, 'adm.ti', false);

create function pg_temp.como(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;
grant execute on function pg_temp.como(text) to authenticated;
create temp table ids (k text primary key, v bigint);
grant select, insert on ids to authenticated;

select is(privado.ciclo_de('2026-10-20') || ' ' || privado.ciclo_de('2026-10-21') || ' ' || privado.ciclo_de('2026-12-25'),
          '2026-10-01 2026-11-01 2027-01-01', 'dias 21 a 20 pertencem ao ciclo do mês seguinte');
select is(privado.ciclo_inicio('2026-10-01') || ' ' || privado.ciclo_fim('2026-10-01'), '2026-09-21 2026-10-20', 'Out/2026 vai de 21/09 a 20/10');
select is(privado.ciclo_inicio('2026-03-01') || ' ' || privado.ciclo_fim('2026-03-01'), '2026-02-21 2026-03-20', 'ciclo de março começa em fevereiro');

select is(privado.minutos_trabalhados('2026-10-19 10:00Z', '2026-10-19 19:00Z', '2026-10-19 14:30Z', '2026-10-19 15:30Z'), 480,
          '07:00 às 16:00 com pausa de 1h = 8h');
select is(privado.minutos_trabalhados('2026-10-19 10:00Z', '2026-10-19 19:00Z', '2026-10-19 15:00Z', '2026-10-19 15:20Z'), 520,
          'pausa de 20 minutos desconta só 20 minutos');
select is(privado.minutos_trabalhados('2026-10-19 10:00Z', '2026-10-19 19:00Z', null, null), 480, 'sem pausa registrada mantém a regra anterior');
select is(privado.minutos_trabalhados('2026-10-19 10:00Z', '2026-10-19 15:00Z', '2026-10-19 14:00Z', null), 240,
          'pausa sem retorno vai até o encerramento');

insert into public.presencas (oficineiro_id, escola_id, data, inicio, fim, pausa_inicio, pausa_fim)
values ('00000000-0000-0000-0000-0000000000a1', (select id from public.escolas), '2026-10-19',
        '2026-10-19 07:00-03', '2026-10-19 16:00-03', '2026-10-19 11:30-03', '2026-10-19 12:30-03');
select privado.calcular_dia(id) from public.presencas where data = '2026-10-19';
select is((select trabalhado_min || ' ' || excedente_status || ' ' || deficit_status from public.presencas where data = '2026-10-19'),
          '480 dentro dentro', 'cálculo do dia desconta a pausa registrada');
select throws_ok($$update public.presencas set pausa_fim = pausa_inicio - interval '1 minute' where data = '2026-10-19'$$, '23514', null,
                 'retorno não pode ser antes da pausa');

select set_config('t.hoje', '2026-10-20', true);
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
insert into public.grade_aulas (dia_semana, horario, inicio, fim, ano, turma, tipo, solucao, componente)
values (1, 4, '10:00', '10:50', 3, 'A', 'R', 'Matific', 'Matemática'),
       (1, 5, '11:00', '11:50', 3, 'B', 'R', 'Matific', 'Matemática'),
       (1, 7, '13:00', '13:50', 3, 'C', 'R', 'Matific', 'Matemática');
select lives_ok($$insert into public.aulas_registro (grade_aula_id, data, inicio, fim, turma, tipo, situacao, solucao, componente, presentes, conteudo, objetivo)
                  select id, '2026-10-19', '00:00', '00:50', 'x', 'R', 'Realizada', 'Matific', 'Matemática', 20, 'Frações no Matific.', 'Sim'
                    from public.grade_aulas where turma = 'A'$$, 'atividade antes da pausa é registrada');
select throws_ok($$insert into public.aulas_registro (grade_aula_id, data, inicio, fim, turma, tipo, situacao, solucao, componente, presentes, conteudo, objetivo)
                   select id, '2026-10-19', '00:00', '00:50', 'x', 'R', 'Realizada', 'Matific', 'Matemática', 20, 'Frações no Matific.', 'Sim'
                     from public.grade_aulas where turma = 'B'$$,
                 '22023', 'a atividade não pode ser registrada dentro do intervalo da pausa para almoço', 'atividade dentro da pausa é recusada');
select lives_ok($$insert into public.aulas_registro (grade_aula_id, data, inicio, fim, turma, tipo, situacao, motivo)
                  select id, '2026-10-19', '00:00', '00:50', 'x', 'R', 'Não realizada', 'Ausência do professor'
                    from public.grade_aulas where turma = 'B'$$, 'na pausa, a atividade pode ser marcada como não realizada');
select lives_ok($$insert into public.aulas_registro (grade_aula_id, data, inicio, fim, turma, tipo, situacao, solucao, componente, presentes, conteudo, objetivo)
                  select id, '2026-10-19', '00:00', '00:50', 'x', 'R', 'Realizada', 'Matific', 'Matemática', 20, 'Frações no Matific.', 'Sim'
                    from public.grade_aulas where turma = 'C'$$, 'atividade depois do retorno é registrada');
select throws_ok($$update public.aulas_registro set situacao = 'Realizada', motivo = null, presentes = 20, conteudo = 'Frações no Matific.', objetivo = 'Sim', solucao = 'Matific', componente = 'Matemática'
                    where turma like '%Turma B%'$$,
                 '22023', null, 'não muda para realizada uma atividade dentro da pausa');
reset role;

select set_config('t.hoje', '2026-10-22', true);
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
select is(privado.mes_editavel(auth.uid(), '2026-10-21'), true, 'dia 21 já está no ciclo atual');
select is(privado.mes_editavel(auth.uid(), '2026-10-20'), false, 'dia 20 pertence ao ciclo que terminou');
select throws_ok($$select public.fechar_relatorio('2026-11-01')$$, '22023', 'o ciclo ainda não terminou: ele fecha sozinho depois do último dia',
                 'ciclo atual não pode ser fechado');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
set local role authenticated;
select is((select count(*)::int from public.relatorios_escola('2026-11-01')), 0, 'ciclo em andamento não gera relatório');
select is((select dias_presenca || ' ' || validos_min || ' ' || registradas || ' ' || realizadas from public.relatorios_escola('2026-10-01')),
          '1 480 3 2', 'ciclo encerrado soma presença e atividades de 21/09 a 20/10');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a0');
set local role authenticated;
select is((select (x ->> 'competencia') || ' ' || (x ->> 'ciclo_inicio') || ' ' || (x ->> 'ciclo_fim') || ' ' || jsonb_array_length(x -> 'presencas')
             from public.admin_consulta('00000000-0000-0000-0000-0000000000a1', '2026-10-01') x),
          '2026-10-01 2026-09-21 2026-10-20 1', 'consulta do administrador usa o ciclo');
select throws_ok($$select public.admin_reabrir_mes('00000000-0000-0000-0000-0000000000a1', '2026-11-01', 'Correção de registro de aula.')$$,
                 '22023', 'o ciclo atual já está aberto', 'ciclo atual já está aberto');
reset role;

select set_config('t.hoje', '', true);
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
select throws_ok($$update public.presencas set pausa_inicio = null$$, '42501', null, 'pausa não é alterada direto na tabela');
reset role;

select * from finish();
rollback;
