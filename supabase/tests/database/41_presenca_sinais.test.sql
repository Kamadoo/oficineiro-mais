begin;
create extension if not exists pgtap with schema extensions;
select plan(13);

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id, latitude, longitude, raio_m) values ('Aaa', 'Aaa - Escola A', 'CS1', -20.0, -43.8, 150);
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000000c1', 'co@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000d1', 'di@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000f1', 'of1@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000f2', 'of2@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000000c1', 'Coordenação', 'coordenador', 'co.x', false);
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha, turno) values
  ('00000000-0000-0000-0000-0000000000d1', 'Direção', 'direcao', (select id from public.escolas where sigla = 'Aaa'), 'di.x', false, null),
  ('00000000-0000-0000-0000-0000000000f1', 'Oficineiro Um', 'oficineiro', (select id from public.escolas where sigla = 'Aaa'), 'of.um', false, 'manha'),
  ('00000000-0000-0000-0000-0000000000f2', 'Oficineiro Dois', 'oficineiro', (select id from public.escolas where sigla = 'Aaa'), 'of.dois', false, 'tarde');

create function pg_temp.como(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;
grant execute on function pg_temp.como(text) to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000000f2');
set local role authenticated;
select lives_ok($$select public.solicitar_ajuste('falta', privado.hoje(), null, null, null, null, 'Consulta médica')$$, 'oficineiro envia justificativa');
reset role;
select set_config('t.aj', (select id from public.presenca_ajustes limit 1)::text, true);

select pg_temp.como('00000000-0000-0000-0000-0000000000d1');
set local role authenticated;
select throws_ok($$select public.sinalizar_ajuste(current_setting('t.aj')::bigint, 'Conferir a justificativa')$$, '42501', null,
                 'direção não sinaliza');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
set local role authenticated;
select throws_ok($$select public.sinalizar_ajuste(current_setting('t.aj')::bigint, '')$$, '22023',
                 'escreva uma mensagem para a direção', 'sinal pede mensagem');
select lives_ok($$select public.sinalizar_ajuste(current_setting('t.aj')::bigint, 'Pendente há dias, favor analisar')$$,
                'coordenação sinaliza a direção');
select throws_ok($$select public.sinalizar_ajuste(current_setting('t.aj')::bigint, 'Lembrando novamente')$$, '22023',
                 'esta solicitação já foi sinalizada há menos de uma hora', 'não repete o sinal em menos de uma hora');
select is((select sinal_qtd from public.relatorio_justificativas()), 1, 'coordenação vê o sinal no relatório');
select is((select count(*)::int from public.relatorio_justificativas(null, privado.hoje() + 1, null)), 0, 'filtro de período');
select throws_ok($$select public.decidir_ajuste(current_setting('t.aj')::bigint, true)$$, '42501', null, 'coordenação não decide');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000f2');
set local role authenticated;
select throws_ok($$select * from public.relatorio_justificativas()$$, '42501', null, 'oficineiro não acessa o relatório nem os sinais');
select is((select count(*)::int from public.presenca_sinais), 0, 'oficineiro não lê a tabela de sinais');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000d1');
set local role authenticated;
select is((select sinal_msg from public.relatorio_justificativas('em_analise')), 'Pendente há dias, favor analisar', 'direção vê o sinal');
select lives_ok($$select public.decidir_ajuste(current_setting('t.aj')::bigint, true)$$, 'direção aprova');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
set local role authenticated;
select is((select analisado_nome from public.relatorio_justificativas()), 'Direção', 'relatório mostra quem decidiu');
reset role;

select * from finish();
rollback;
