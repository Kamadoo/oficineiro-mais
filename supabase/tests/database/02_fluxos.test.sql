begin;
create extension if not exists pgtap with schema extensions;
create or replace function privado.hoje() returns date language sql stable set search_path = ''
  as $$ select coalesce(nullif(current_setting('t.hoje', true), '')::date, (now() at time zone 'America/Sao_Paulo')::date) $$;
select plan(15);

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id, latitude, longitude) values ('Aaa', 'Aaa - Escola Teste', 'CS1', -19.98, -43.85);
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000b1', 'coord@exemplo.test'),
  ('00000000-0000-0000-0000-0000000000b2', 'direcao@exemplo.test'),
  ('00000000-0000-0000-0000-0000000000b3', 'ofic@exemplo.test');
insert into public.perfis (id, nome, papel, escola_id) values
  ('00000000-0000-0000-0000-0000000000b1', 'Coord Teste', 'coordenador', null),
  ('00000000-0000-0000-0000-0000000000b2', 'Direcao Teste', 'direcao', (select id from public.escolas where sigla = 'Aaa')),
  ('00000000-0000-0000-0000-0000000000b3', 'Oficineiro Teste', 'oficineiro', (select id from public.escolas where sigla = 'Aaa'));
update public.perfis set trocar_senha = false;

create function pg_temp.como(p_uid text, p_aal text default 'aal2') returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
$$;
grant execute on function pg_temp.como(text, text) to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000000b3', 'aal2');
set local role authenticated;
select throws_ok($$select public.solicitar_ajuste('esquecimento', privado.hoje(), '07:00', null, null, '15:00', 'Ok')$$, '22023', null,
                 'oficineiro: motivo curto é recusado');
select lives_ok($$select public.solicitar_ajuste('esquecimento', privado.hoje(), '07:00', null, null, '15:00', 'Esqueci de registrar a entrada e a saída.')$$,
                'oficineiro: solicita o ajuste');
select set_config('t.aj', (select id from public.presenca_ajustes limit 1)::text, true);
select throws_ok(format('select public.decidir_ajuste(%s, true)', current_setting('t.aj')), '42501', null,
                 'oficineiro: não aprova a própria solicitação');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000b1', 'aal2');
set local role authenticated;
select throws_ok(format('select public.decidir_ajuste(%s, true)', current_setting('t.aj')), '42501', null,
                 'coordenação: acompanha, mas não decide a solicitação');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000b2', 'aal1');
set local role authenticated;
select throws_ok(format('select public.decidir_ajuste(%s, true)', current_setting('t.aj')), '42501', null,
                 'direção sem MFA: não decide');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000b2', 'aal2');
set local role authenticated;
select lives_ok(format('select public.decidir_ajuste(%s, true)', current_setting('t.aj')), 'direção com MFA: aprova');
reset role;
select is((select status from public.presenca_ajustes), 'aprovada', 'solicitação ficou aprovada');

select pg_temp.como('00000000-0000-0000-0000-0000000000b3', 'aal2');
set local role authenticated;
select throws_ok($$select public.fechar_relatorio(privado.ciclo_de(privado.hoje()))$$, '22023', null, 'oficineiro: não fecha o ciclo antes de ele terminar');
select set_config('t.hoje', (privado.ciclo_fim(privado.ciclo_de(privado.hoje())) + 1)::text, true);
select set_config('t.rel', public.fechar_relatorio(privado.hoje() - 1)::text, true);
select throws_ok($$select public.fechar_relatorio(privado.hoje() - 1)$$, '22023', null, 'oficineiro: não fecha o mesmo mês duas vezes');
select throws_ok(format('select public.aprovar_relatorio(%s)', current_setting('t.rel')), '42501', null, 'oficineiro: não aprova o próprio relatório');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000b1', 'aal2');
set local role authenticated;
select throws_ok(format('select public.aprovar_relatorio(%s)', current_setting('t.rel')), '42501', null,
                 'coordenação: não pula a etapa da direção');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000b2', 'aal2');
set local role authenticated;
select lives_ok(format('select public.aprovar_relatorio(%s)', current_setting('t.rel')), 'direção: aprova');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000b1', 'aal2');
set local role authenticated;
select lives_ok(format('select public.devolver_relatorio(%s, %L)', current_setting('t.rel'), 'Faltou a reunião do dia 08'), 'coordenação: devolve com motivo');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000b3', 'aal2');
set local role authenticated;
select is(privado.mes_editavel('00000000-0000-0000-0000-0000000000b3', privado.hoje() - 1), true, 'relatório devolvido: mês volta a ser editável');
select is(public.fechar_relatorio(privado.hoje() - 1)::text, current_setting('t.rel'), 'oficineiro: fecha de novo o mesmo relatório');
reset role;

select * from finish();
rollback;
