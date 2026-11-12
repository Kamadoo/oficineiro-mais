begin;
create extension if not exists pgtap with schema extensions;
select plan(35);

create or replace function privado.hoje() returns date language sql stable set search_path = ''
  as $$ select coalesce(nullif(current_setting('t.hoje', true), '')::date, (now() at time zone 'America/Sao_Paulo')::date) $$;
select set_config('t.hoje', '2026-10-22', true);

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Aaa', 'Aaa - Escola A', 'CS1');
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000000a0', 'adm@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000c1', 'co@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000d1', 'ge@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000f1', 'of@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000000a0', 'Administração TI', 'administrador', 'adm.ti', false),
  ('00000000-0000-0000-0000-0000000000c1', 'Coordenação', 'coordenador', 'co.x', false),
  ('00000000-0000-0000-0000-0000000000d1', 'Gerência', 'gerente', 'ge.x', false);
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha)
  values ('00000000-0000-0000-0000-0000000000f1', 'Oficineiro F', 'oficineiro', (select id from public.escolas), 'of.f', false);

create function pg_temp.dia(p_data date, p_ini text, p_fim text) returns bigint language sql as $$
  insert into public.presencas (oficineiro_id, escola_id, data, inicio, fim)
  values ('00000000-0000-0000-0000-0000000000f1', (select id from public.escolas), p_data,
          (p_data + p_ini::time) at time zone 'America/Sao_Paulo', (p_data + p_fim::time) at time zone 'America/Sao_Paulo')
  returning id;
$$;
create temp table ids (k text primary key, v bigint);
grant select on ids to authenticated;
insert into ids values ('seg', pg_temp.dia('2026-10-19', '07:00', '15:00'));
select privado.calcular_dia(v) from ids;
insert into public.grade_aulas (oficineiro_id, escola_id, ano_letivo, dia_semana, inicio, fim, ano, turma, tipo, solucao, componente)
  values ('00000000-0000-0000-0000-0000000000f1', (select id from public.escolas), 2026, 1, '07:00', '07:50', 3, 'A', 'R', 'Matific', 'Matemática');
insert into public.grade_envios (oficineiro_id, escola_id, ano_letivo, status) values ('00000000-0000-0000-0000-0000000000f1', (select id from public.escolas), 2026, 'validada');
insert into public.aulas_registro (oficineiro_id, escola_id, grade_aula_id, data, inicio, fim, turma, tipo, situacao, presentes, matriculados, conteudo, componente)
  select g.oficineiro_id, g.escola_id, g.id, '2026-10-19', g.inicio, g.fim, 'A', g.tipo, 'Realizada', 20, 25, 'Aula de frações com blocos.', 'Matemática' from public.grade_aulas g;
insert into ids values ('reg', (select id from public.aulas_registro limit 1));

create function pg_temp.como(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;
grant execute on function pg_temp.como(text) to authenticated;
create function pg_temp.pres(p_k text) returns text language sql security definer as $$
  select trabalhado_min || ' ' || deficit_min || ' ' || deficit_status from public.presencas where id = (select v from ids where k = p_k);
$$;
grant execute on function pg_temp.pres(text) to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000000d1');
set local role authenticated;
select throws_ok($$select public.admin_salvar_configuracoes('ti@exemplo.test', null, null)$$, '42501', null, 'gerência não altera configurações');
select throws_ok($$select public.admin_corrigir_presenca((select v from ids where k = 'seg'), '2026-10-19 10:00Z', '2026-10-19 20:00Z', 'Correção pedida pela escola')$$, '42501', null, 'gerência não corrige presença');
select throws_ok($$update public.perfis set nome = 'Trocado' where id = '00000000-0000-0000-0000-0000000000a0'$$, '42501', null, 'gerência não altera a conta do administrador');
select is((select count(*)::int from public.contas_gestao() where papel = 'administrador'), 0, 'gerência não vê a conta do administrador');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a0');
set local role authenticated;
select throws_ok($$select public.enviar_lembrete((select id from public.grade_aulas limit 1), '2026-10-19')$$, '42501', null, 'administrador não envia lembretes');

select throws_ok($$select public.admin_salvar_configuracoes('não é e-mail', null, null)$$, '22023', null, 'e-mail inválido é recusado');
select lives_ok($$select public.admin_salvar_configuracoes('TI@Exemplo.test', '(31) 3333-4444', 'Segunda a sexta, das 8h às 17h')$$, 'administrador salva o contato do suporte');
select is((select suporte_email || ' ' || suporte_telefone || ' ' || suporte_horario from public.configuracoes), 'ti@exemplo.test 3133334444 Segunda a sexta, das 8h às 17h', 'contato gravado');

select is(privado.minutos_previstos('2026-10-23'), 480, 'dia útil prevê 8 horas');
select lives_ok($$select public.admin_salvar_feriado('2026-10-23', 'Recesso escolar', 'recesso')$$, 'cadastra recesso');
select is(privado.minutos_previstos('2026-10-23'), 0, 'recesso deixa de prever horas');
select throws_ok($$select public.admin_salvar_feriado('2026-10-24', 'X', 'feriado')$$, '22023', null, 'nome curto é recusado');
select lives_ok($$select public.admin_remover_feriado('2026-10-23')$$, 'remove o recesso');
select is(privado.minutos_previstos('2026-10-23'), 480, 'dia volta a prever 8 horas');
select throws_ok($$select public.admin_remover_feriado('2026-10-23')$$, '22023', null, 'não remove o que não existe');

select is(jsonb_array_length(public.admin_consulta('00000000-0000-0000-0000-0000000000f1', '2026-10-01') -> 'presencas'), 1, 'consulta traz as presenças do mês');
select is(jsonb_array_length(public.admin_consulta('00000000-0000-0000-0000-0000000000f1', '2026-10-01') -> 'registros'), 1, 'consulta traz os registros do mês');
select is(public.admin_consulta('00000000-0000-0000-0000-0000000000f1', '2026-10-01') -> 'grades' -> 0 ->> 'status', 'validada', 'consulta traz a situação da grade');

select is(pg_temp.pres('seg'), '480 0 dentro', 'presença de 8 horas antes da correção');
select throws_ok($$select public.admin_corrigir_presenca((select v from ids where k = 'seg'), '2026-10-19 10:00Z', '2026-10-19 19:00Z', 'curto')$$, '22023', null, 'correção exige motivo');
select throws_ok($$select public.admin_corrigir_presenca((select v from ids where k = 'seg'), '2026-10-19 10:00Z', '2026-10-19 09:00Z', 'Horário informado pela direção')$$, '22023', null, 'encerramento antes do início é recusado');
select lives_ok($$select public.admin_corrigir_presenca((select v from ids where k = 'seg'), '2026-10-19 10:00Z', '2026-10-19 19:00Z', 'Encerramento registrado errado pelo celular')$$, 'corrige o encerramento');
select is(pg_temp.pres('seg'), '540 0 dentro', 'horas recalculadas depois da correção, sem desconto automático de almoço');

select lives_ok($$select public.admin_lancar_presenca('00000000-0000-0000-0000-0000000000f1', '2026-10-20 10:00Z', '2026-10-20 19:00Z', 'Celular sem bateria no dia, confirmado pela direção')$$, 'lança presença de um dia sem registro');
select is((select conferencia || ' ' || conferencia_status || ' ' || trabalhado_min from public.presencas where data = '2026-10-20'), 'Lançada pelo administrador conferida 540', 'presença lançada fica marcada e calculada');
select throws_ok($$select public.admin_lancar_presenca('00000000-0000-0000-0000-0000000000f1', '2026-10-20 11:00Z', null, 'Tentativa de lançar de novo')$$, '22023', null, 'não lança duas presenças no mesmo dia');
select throws_ok($$select public.admin_lancar_presenca('00000000-0000-0000-0000-0000000000f1', '2026-10-30 10:00Z', null, 'Lançamento adiantado')$$, '22023', null, 'não lança presença futura');

select lives_ok($$select public.admin_reabrir_mes('00000000-0000-0000-0000-0000000000f1', '2026-09-01', 'Faltou registrar duas aulas de setembro')$$, 'reabre mês anterior');
select is(privado.mes_editavel('00000000-0000-0000-0000-0000000000f1', '2026-09-15'), true, 'mês reaberto volta a ser editável pelo oficineiro');
select throws_ok($$select public.admin_reabrir_mes('00000000-0000-0000-0000-0000000000f1', '2026-09-01', 'Faltou registrar duas aulas de setembro')$$, '22023', null, 'não reabre o que já está aberto');

select lives_ok($$select public.admin_situacao_grade('00000000-0000-0000-0000-0000000000f1', 2026::smallint, 'devolvida', 'Validação feita por engano, revisar turmas')$$, 'devolve grade validada');
select is((select status || ' ' || comentario from public.grade_envios), 'devolvida Validação feita por engano, revisar turmas', 'grade devolvida com o motivo');

select lives_ok($$select public.admin_situacao_registro((select v from ids where k = 'reg'), 'anulado', 'Registro duplicado no sistema')$$, 'anula registro');
select lives_ok($$select public.admin_situacao_registro((select v from ids where k = 'reg'), '', 'Anulação feita por engano')$$, 'desfaz a anulação');
select is((select count(*)::int from public.admin_auditoria(p_acao => 'ADMIN_CORRECAO')), 6, 'todas as correções ficam na auditoria');
reset role;

select * from finish();
rollback;
