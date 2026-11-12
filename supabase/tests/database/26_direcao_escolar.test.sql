begin;
create extension if not exists pgtap with schema extensions;
select plan(34);

create or replace function privado.hoje() returns date language sql stable set search_path = ''
  as $$ select coalesce(nullif(current_setting('t.hoje', true), '')::date, (now() at time zone 'America/Sao_Paulo')::date) $$;
select set_config('t.hoje', '2026-10-22', true);

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Aaa', 'Aaa - Escola A', 'CS1'), ('Bbb', 'Bbb - Escola B', 'CS1');
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000000c1', 'co@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000e1', 'dir@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000f1', 'of@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000f2', 'of2@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000f3', 'of3@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000000c1', 'Coordenação', 'coordenador', 'co.x', false);
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000000e1', 'Direção A', 'direcao', (select id from public.escolas where sigla = 'Aaa'), 'dir.a', false),
  ('00000000-0000-0000-0000-0000000000f1', 'Oficineiro F', 'oficineiro', (select id from public.escolas where sigla = 'Aaa'), 'of.f', false),
  ('00000000-0000-0000-0000-0000000000f2', 'Oficineiro G', 'oficineiro', (select id from public.escolas where sigla = 'Bbb'), 'of.g', false),
  ('00000000-0000-0000-0000-0000000000f3', 'Oficineiro H', 'oficineiro', (select id from public.escolas where sigla = 'Aaa'), 'of.h', false);

create temp table ids (k text primary key, v bigint);
grant select on ids to authenticated;
create function pg_temp.aula(p_of text, p_data date, p_ini text, p_sit text, p_pres smallint) returns bigint language sql as $$
  insert into public.aulas_registro (oficineiro_id, escola_id, data, inicio, fim, turma, tipo, situacao, presentes, matriculados, conteudo, motivo)
  select p.id, p.escola_id, p_data, p_ini::time, p_ini::time + interval '50 minutes', '3A', 'R', p_sit,
         case when p_sit = 'Não realizada' then null else p_pres end, 25, 'Aula de frações.',
         case when p_sit = 'Não realizada' then 'Sem internet' end
    from public.perfis p where p.id = p_of::uuid
  returning id;
$$;
insert into ids values
  ('a1', pg_temp.aula('00000000-0000-0000-0000-0000000000f1', '2026-09-14', '07:00', 'Realizada', 20::smallint)),
  ('a2', pg_temp.aula('00000000-0000-0000-0000-0000000000f1', '2026-09-14', '08:00', 'Realizada', 22::smallint)),
  ('a3', pg_temp.aula('00000000-0000-0000-0000-0000000000f1', '2026-09-15', '07:00', 'Não realizada', null)),
  ('a4', pg_temp.aula('00000000-0000-0000-0000-0000000000f1', '2026-09-15', '08:00', 'Pendente de registro', null)),
  ('b1', pg_temp.aula('00000000-0000-0000-0000-0000000000f2', '2026-09-14', '07:00', 'Realizada', 18::smallint)),
  ('o1', pg_temp.aula('00000000-0000-0000-0000-0000000000f1', '2026-10-20', '07:00', 'Realizada', 21::smallint));
insert into public.presencas (oficineiro_id, escola_id, data, inicio, fim)
select '00000000-0000-0000-0000-0000000000f1', (select id from public.escolas where sigla = 'Aaa'), d,
       (d + time '07:00') at time zone 'America/Sao_Paulo', (d + time '16:00') at time zone 'America/Sao_Paulo'
  from (values (date '2026-09-14'), (date '2026-09-15')) v(d);
select privado.calcular_dia(id) from public.presencas;

create function pg_temp.como(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;
grant execute on function pg_temp.como(text) to authenticated;
create function pg_temp.ck(p_k text) returns text language sql security definer as $$
  select coalesce(check_direcao, '-') || ' ' || coalesce(check_motivo, '-') from public.aulas_registro where id = (select v from ids where k = p_k);
$$;
grant execute on function pg_temp.ck(text) to authenticated;
create function pg_temp.rel(p_of text) returns text language sql security definer as $$
  select status || ' ' || coalesce(motivo_devolucao, '-') || ' ' || (devolvido_por is not null) || ' ' || coalesce(devolvido_papel, '-') from public.relatorios_mensais
   where oficineiro_id = p_of::uuid and competencia = '2026-09-01';
$$;
grant execute on function pg_temp.rel(text) to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000000f1');
set local role authenticated;
select throws_ok($$select * from public.relatorios_escola('2026-09-01')$$, '42501', null, 'oficineiro não lista relatórios da escola');
select throws_ok($$select public.conferir_aula((select v from ids where k = 'a1'), true)$$, '42501', null, 'oficineiro não faz o check da direção');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000e1');
set local role authenticated;
select is((select count(*)::int from public.relatorios_escola('2026-11-01')), 0, 'ciclo em andamento não gera relatório');
select is((select count(*)::int from public.relatorios_escola('2026-09-01')), 1, 'mês encerrado gera o relatório de quem teve atividade na escola');
select is((select oficineiro || ' ' || status from public.relatorios_escola('2026-09-01')), 'Oficineiro F fechado', 'relatório fechado do oficineiro da escola');
select is((select dias_presenca || ' ' || validos_min from public.relatorios_escola('2026-09-01')), '2 960', 'dias e horas válidas do mês');
select is((select registradas || ' ' || realizadas || ' ' || nao_realizadas || ' ' || estudantes from public.relatorios_escola('2026-09-01')), '3 2 1 42', 'aulas e estudantes do mês');
select is((select count(*)::int from public.relatorios_escola('2026-09-01') where escola like 'Bbb%'), 0, 'direção não vê outra escola');

select throws_ok($$select public.conferir_aula((select v from ids where k = 'a4'), true)$$, '22023', null, 'aula sem registro não recebe check');
select throws_ok($$select public.conferir_aula((select v from ids where k = 'b1'), true)$$, '42501', null, 'direção não confere aula de outra escola');
select throws_ok($$select public.conferir_aula((select v from ids where k = 'a2'), false, 'x')$$, '22023', null, 'contestação exige motivo');
select lives_ok($$select public.conferir_aula((select v from ids where k = 'a2'), false, 'Turma diferente · era o 4º ano')$$, 'contesta uma aula');
select is(pg_temp.ck('a2'), 'contestada Turma diferente · era o 4º ano', 'contestação gravada com motivo');
select is(public.conferir_aulas(array[(select v from ids where k = 'a1'), (select v from ids where k = 'a2'), (select v from ids where k = 'a3'), (select v from ids where k = 'a4'), (select v from ids where k = 'b1')]), 2, 'confirmar todas só confirma as registradas ainda sem check');
select is(pg_temp.ck('a1') || ' | ' || pg_temp.ck('a3') || ' | ' || pg_temp.ck('b1'), 'ok - | ok - | - -', 'confirmadas na escola, outra escola intacta');
select is((select confirmadas || ' ' || contestadas from public.relatorios_escola('2026-09-01')), '2 1', 'relatório conta confirmadas e contestadas');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000f1');
set local role authenticated;
select lives_ok($$update public.aulas_registro set turma = '4A', conteudo = 'Aula de frações no 4º ano.' where id = (select v from ids where k = 'a2')$$, 'oficineiro corrige aula contestada mesmo com o mês fechado');
select is(pg_temp.ck('a2'), 'corrigida Turma diferente · era o 4º ano', 'aula volta para novo check da direção');
select is((select count(*)::int from public.aulas_registro where id = (select v from ids where k = 'a1')), 1, 'oficineiro vê a própria aula');
update public.aulas_registro set conteudo = 'Tentativa de alterar aula confirmada' where id = (select v from ids where k = 'a1');
select is((select conteudo from public.aulas_registro where id = (select v from ids where k = 'a1')), 'Aula de frações.', 'aula confirmada pela direção não muda');
update public.aulas_registro set conteudo = 'Tentativa fora do prazo' where id = (select v from ids where k = 'a3');
select is((select conteudo from public.aulas_registro where id = (select v from ids where k = 'a3')), 'Aula de frações.', 'aula sem contestação em mês fechado não muda');
select throws_ok($$update public.aulas_registro set check_direcao = 'ok' where id = (select v from ids where k = 'a2')$$, '42501', null, 'oficineiro não marca o próprio check');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000e1');
set local role authenticated;
select is(public.conferir_aulas(array[(select v from ids where k = 'a2')]), 1, 'aula corrigida entra no confirmar todas');
select throws_ok($$select public.devolver_relatorio((select id from public.relatorios_escola('2026-09-01')), 'ok')$$, '22023', null, 'devolução exige motivo');
select lives_ok($$select public.devolver_relatorio((select id from public.relatorios_escola('2026-09-01')), 'Faltou registrar a aula de 15/09 às 08h')$$, 'direção devolve o relatório');
select is(pg_temp.rel('00000000-0000-0000-0000-0000000000f1'), 'devolvido Faltou registrar a aula de 15/09 às 08h true direcao', 'devolução registra motivo e quem devolveu');
select is((select devolvido_nome || ' ' || devolvido_papel from public.relatorios_escola('2026-09-01')), 'Direção A direcao', 'lista mostra quem devolveu');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000f1');
set local role authenticated;
select lives_ok($$select public.fechar_relatorio('2026-09-01')$$, 'oficineiro reenvia o mês');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000e1');
set local role authenticated;
select lives_ok($$select public.aprovar_relatorio((select id from public.relatorios_escola('2026-09-01')))$$, 'direção aprova');
select throws_ok($$select public.aprovar_relatorio((select id from public.relatorios_escola('2026-09-01')))$$, '42501', null, 'direção não aprova duas vezes');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
set local role authenticated;
select is((select count(*)::int from public.relatorios_escola('2026-09-01')), 2, 'coordenação vê os relatórios de todas as escolas');
select is((select status || ' ' || direcao_nome from public.relatorios_escola('2026-09-01') where oficineiro = 'Oficineiro F'), 'aprovado_direcao Direção A', 'coordenação vê a aprovação da direção');
select lives_ok($$select public.aprovar_relatorio((select id from public.relatorios_escola('2026-09-01') where oficineiro = 'Oficineiro F'))$$, 'coordenação faz a aprovação final');
select throws_ok($$select public.aprovar_relatorio((select id from public.relatorios_escola('2026-09-01') where oficineiro = 'Oficineiro G'))$$, '42501', null, 'coordenação só aprova depois da direção');
reset role;

select * from finish();
rollback;
