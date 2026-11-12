begin;
create extension if not exists pgtap with schema extensions;
select plan(25);

create or replace function privado.hoje() returns date language sql stable set search_path = ''
  as $$ select coalesce(nullif(current_setting('t.hoje', true), '')::date, (now() at time zone 'America/Sao_Paulo')::date) $$;

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Aaa', 'Aaa - Escola A', 'CS1');
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000000a1', 'of.a@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000b1', 'of.b@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000c1', 'co@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha)
select x.id::uuid, x.nome, 'oficineiro', e.id, x.usuario, false
  from (values ('00000000-0000-0000-0000-0000000000a1', 'Oficineiro A', 'of.a'),
               ('00000000-0000-0000-0000-0000000000b1', 'Oficineiro B', 'of.b')) x(id, nome, usuario)
  cross join public.escolas e;
insert into public.perfis (id, nome, papel, usuario, trocar_senha) values ('00000000-0000-0000-0000-0000000000c1', 'Coordenação', 'coordenador', 'co.x', false);

create temp table dia as
select max(x)::date as d from generate_series(privado.ciclo_inicio(privado.ciclo_de(privado.hoje())), privado.hoje(), interval '1 day') x
 where extract(isodow from x) <= 5;
grant select on dia to authenticated;
insert into public.presencas (oficineiro_id, escola_id, data, inicio, fim)
select p.id, p.escola_id, d, (d + time '07:00') at time zone 'America/Sao_Paulo', (d + time '12:00') at time zone 'America/Sao_Paulo'
  from dia, public.perfis p where p.id = '00000000-0000-0000-0000-0000000000a1';

create function pg_temp.como(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;
grant execute on function pg_temp.como(text) to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
insert into public.grade_aulas (dia_semana, inicio, fim, ano, turma, tipo, solucao, componente)
select extract(isodow from d), '07:50', '09:30', 3, 'B', 'R', 'Matific', 'Matemática' from dia;
insert into public.grade_aulas (dia_semana, inicio, fim, ano, turma, tipo, oficina)
select extract(isodow from d), '10:40', '11:30', 4, 'A', 'P', 'Programa Construtores – Minecraft' from dia;
insert into public.aulas_registro (grade_aula_id, data, inicio, fim, turma, tipo, situacao, presentes, matriculados, conteudo)
select g.id, d.d, g.inicio, g.fim, 'x', g.tipo, 'Realizada', 20, 25, 'Aula de frações com blocos.' from public.grade_aulas g, dia d where g.ano = 3;
reset role;

create temp table ids as select (select id from public.aulas_registro) as reg, (select id from public.grade_aulas where ano = 4) as livre, (select d from dia) as d;
grant select on ids to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
select throws_ok($$select public.revisar_aula((select reg from ids), 'revisado')$$, '42501', null, 'oficineiro não revisa aula');
select throws_ok($$update public.aulas_registro set revisao_status = 'revisado'$$, '42501', null, 'oficineiro não muda a revisão direto');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
set local role authenticated;
select lives_ok($$select public.revisar_aula((select reg from ids), 'revisado')$$, 'coordenador marca como revisado');
select is((select revisao_status from public.aulas_registro), 'revisado', 'revisão gravada');
select throws_ok($$select public.revisar_aula((select reg from ids), 'devolvido', 'ok')$$, '22023', null, 'devolver exige explicação');
select throws_ok($$select public.revisar_aula((select reg from ids), 'apagar', 'qualquer coisa')$$, '22023', null, 'ação desconhecida é recusada');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
select lives_ok($$update public.aulas_registro set presentes = 21$$, 'oficineiro edita aula revisada dentro do mês');
select is((select revisao_status from public.aulas_registro), null, 'editar aula revisada volta para aguardando revisão');
reset role;

update public.aulas_registro set check_direcao = 'ok', check_por = '00000000-0000-0000-0000-0000000000c1', check_em = now();
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
set local role authenticated;
select lives_ok($$select public.revisar_aula((select reg from ids), 'devolvido', 'Faltou contar o que foi feito.')$$, 'coordenador devolve com explicação');
reset role;
select is((select revisao_status || ' / ' || revisao_obs || ' / ' || coalesce(check_direcao, 'sem check') from public.aulas_registro),
          'devolvido / Faltou contar o que foi feito. / sem check', 'devolução gravada e confirmação da direção zerada');

select set_config('t.hoje', (privado.ciclo_fim(privado.ciclo_de((select d from ids))) + 4)::text, true);
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
select lives_ok($$update public.aulas_registro set conteudo = 'Aula de frações com blocos e registro no caderno.'$$, 'devolvido pode ser corrigido mesmo depois do fim do ciclo');
select is((select revisao_status || ' / ' || revisao_obs from public.aulas_registro), 'corrigido / Faltou contar o que foi feito.', 'correção fica marcada e mantém o comentário');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
set local role authenticated;
select lives_ok($$select public.revisar_aula((select reg from ids), 'anulado', 'Aula registrada em duplicidade.')$$, 'coordenador anula com justificativa');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
update public.aulas_registro set presentes = 1;
select is((select presentes::int from public.aulas_registro), 21, 'aula anulada não pode ser editada');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
set local role authenticated;
select lives_ok($$select public.revisar_aula((select reg from ids), 'aguardando')$$, 'coordenador pode desfazer a decisão');
reset role;
select is((select coalesce(revisao_status, 'aguardando') from public.aulas_registro), 'aguardando', 'decisão desfeita');
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
update public.aulas_registro set presentes = 2;
select is((select presentes::int from public.aulas_registro), 21, 'sem devolução, ciclo encerrado continua travado');
reset role;

select set_config('t.hoje', '', true);
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
select throws_ok($$select public.enviar_lembrete((select livre from ids), (select d from ids))$$, '42501', null, 'oficineiro não envia lembrete');
select throws_ok($$insert into public.lembretes_registro (oficineiro_id, escola_id, grade_aula_id, data, enviado_por)
                   select '00000000-0000-0000-0000-0000000000a1', 1, livre, d, '00000000-0000-0000-0000-0000000000a1' from ids$$, '42501', null, 'lembrete não é gravado direto');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
set local role authenticated;
select lives_ok($$select public.enviar_lembrete((select livre from ids), (select d from ids))$$, 'coordenador envia lembrete de aula sem registro');
select throws_ok($$select public.enviar_lembrete((select livre from ids), (select d from ids))$$, '22023', null, 'não repete o lembrete no mesmo dia');
select throws_ok($$select public.enviar_lembrete((select (select id from public.grade_aulas where ano = 3)), (select d from ids))$$, '22023', null, 'não envia lembrete de aula já registrada');
select throws_ok($$select public.enviar_lembrete((select livre from ids), (select d + 7 from ids))$$, '22023', null, 'não envia lembrete de aula futura');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
select is((select count(*)::int from public.meus_lembretes()), 1, 'oficineiro vê o lembrete');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
set local role authenticated;
select is((select count(*)::int from public.lembretes_registro), 0, 'outro oficineiro não vê o lembrete');
reset role;

select * from finish();
rollback;
