begin;
create extension if not exists pgtap with schema extensions;
select plan(33);

create or replace function privado.hoje() returns date language sql stable set search_path = ''
  as $$ select coalesce(nullif(current_setting('t.hoje', true), '')::date, (now() at time zone 'America/Sao_Paulo')::date) $$;

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Aaa', 'Aaa - Escola A', 'CS1'), ('Bbb', 'Bbb - Escola B', 'CS1'), ('Ccc', 'Ccc - Escola C', 'CS1');
update public.escolas set ativa = false where sigla = 'Ccc';
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000000a1', 'of.a@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000b1', 'of.b@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000c1', 'co@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000d1', 'ge@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000e1', 'novo@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000f1', 'adm@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha, telefone) values
  ('00000000-0000-0000-0000-0000000000a1', 'Oficineiro A', 'oficineiro', (select id from public.escolas where sigla = 'Aaa'), 'of.a', false, '31999990000'),
  ('00000000-0000-0000-0000-0000000000b1', 'Oficineiro B', 'oficineiro', (select id from public.escolas where sigla = 'Aaa'), 'of.b', false, null),
  ('00000000-0000-0000-0000-0000000000e1', 'Pessoa Nova', 'oficineiro', (select id from public.escolas where sigla = 'Bbb'), null, true, null);
insert into public.perfis (id, nome, papel, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000000c1', 'Coordenação', 'coordenador', 'co.x', false),
  ('00000000-0000-0000-0000-0000000000d1', 'Gerência', 'gerente', 'ge.x', false),
  ('00000000-0000-0000-0000-0000000000f1', 'Administração', 'administrador', 'adm.x', false);
select public.fsm_definir_cpf('00000000-0000-0000-0000-0000000000a1', '52998224725');

create function pg_temp.como(p_uid text, p_aal text default 'aal2') returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
$$;
grant execute on function pg_temp.como(text, text) to authenticated;
create temp table esc as select (select id from public.escolas where sigla = 'Aaa') a, (select id from public.escolas where sigla = 'Bbb') b, (select id from public.escolas where sigla = 'Ccc') c;
grant select on esc to authenticated;

set local role anon;
select throws_ok($$select * from public.contas_gestao()$$, '42501', null, 'sem login não lista contas');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
select throws_ok($$select * from public.contas_gestao()$$, '42501', null, 'oficineiro não lista contas');
select throws_ok($$select public.alterar_escola('00000000-0000-0000-0000-0000000000b1', (select b from esc), privado.hoje(), 'Outro')$$, '42501', null, 'oficineiro não muda escola');
select throws_ok($$select telefone from public.perfis$$, '42501', null, 'telefone não é legível pela API');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000c1', 'aal1');
set local role authenticated;
select throws_ok($$select * from public.contas_gestao()$$, '42501', null, 'coordenador sem autenticador não lista contas');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
set local role authenticated;
select is((select count(*)::int from public.contas_gestao()), 4, 'coordenador vê os oficineiros e a própria conta, sem a gerência');
select is((select usuario || ' / ' || telefone from public.contas_gestao() where nome = 'Oficineiro A'), 'of.a / 31999990000', 'lista traz login e telefone');
select is((select primeiro_acesso from public.contas_gestao() where nome = 'Pessoa Nova'), true, 'conta nova aparece aguardando primeiro acesso');
select ok((select string_agg(concat_ws(' ', t.id, t.nome, t.usuario, t.papel, t.escola_id, t.carteira_id, t.telefone, t.mudanca_motivo), ' ') from public.contas_gestao() t) !~ '529|998|224|725'
          and (select string_agg(t::text, ' ') from public.contas_gestao() t) !~ '52998224725|529\.982|982\.247|224-?725', 'lista não traz CPF');
select is((select nome from public.contas_gestao() where eu), 'Coordenação', 'lista marca a própria conta');
select throws_ok($$select public.alterar_escola('00000000-0000-0000-0000-0000000000c1', (select b from esc), privado.hoje(), 'Outro')$$, '22023', null, 'não altera a própria conta');
select throws_ok($$select public.alterar_escola('00000000-0000-0000-0000-0000000000d1', (select b from esc), privado.hoje(), 'Outro')$$, '22023', null, 'só oficineiro muda de escola');
select throws_ok($$select public.alterar_escola('00000000-0000-0000-0000-0000000000a1', (select a from esc), privado.hoje(), 'Outro')$$, '22023', null, 'recusa a mesma escola');
select throws_ok($$select public.alterar_escola('00000000-0000-0000-0000-0000000000a1', (select c from esc), privado.hoje(), 'Outro')$$, '22023', null, 'recusa escola inativa');
select throws_ok($$select public.alterar_escola('00000000-0000-0000-0000-0000000000a1', (select b from esc), privado.hoje(), 'Porque sim')$$, '22023', null, 'recusa motivo fora da lista');
select throws_ok($$select public.alterar_escola('00000000-0000-0000-0000-0000000000a1', (select b from esc), privado.hoje() - 1, 'Outro')$$, '22023', null, 'recusa data passada');
select throws_ok($$select public.alterar_escola('00000000-0000-0000-0000-0000000000a1', (select b from esc), privado.hoje(), 'Remanejamento do núcleo')$$, '22023', null, 'coordenador não aplica a mudança na hora');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000f1');
set local role authenticated;
select is(public.alterar_escola('00000000-0000-0000-0000-0000000000a1', (select b from esc), privado.hoje(), 'Remanejamento do núcleo'), 'aplicada', 'administrador aplica a mudança na hora');
reset role;
select is((select escola_id from public.perfis where usuario = 'of.a'), (select b from esc), 'escola do oficineiro alterada');
select ok(exists (select 1 from auditoria.eventos where tabela = 'mudancas_escola'), 'mudança fica na auditoria');

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
set local role authenticated;
select is(public.alterar_escola('00000000-0000-0000-0000-0000000000b1', (select b from esc), privado.hoje() + 10, 'Outro'), 'agendada', 'mudança futura fica agendada');
select is(public.alterar_escola('00000000-0000-0000-0000-0000000000b1', (select b from esc), privado.hoje() + 12, 'Solicitação da SEMED'), 'agendada', 'agendar de novo substitui a anterior');
select is((select mudanca_vale - privado.hoje() from public.contas_gestao() where nome = 'Oficineiro B'), 12, 'lista mostra a mudança agendada');
reset role;
select is((select count(*)::int from public.mudancas_escola where usuario_id = '00000000-0000-0000-0000-0000000000b1' and cancelada_em is null), 1, 'só uma mudança pendente por conta');

select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
set local role authenticated;
select is(public.minha_mudanca_escola() ->> 'escola', 'Bbb - Escola B', 'oficineiro é avisado da nova escola');
select is(privado.escola_atual(), (select a from esc), 'antes da data continua na escola atual');
select throws_ok($$insert into public.mudancas_escola (usuario_id, escola_anterior, escola_nova, vale_a_partir, motivo, criado_por)
                   values (auth.uid(), 1, 2, privado.hoje(), 'Outro', auth.uid())$$, '42501', null, 'mudança não é gravada direto');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
select is((select count(*)::int from public.mudancas_escola where usuario_id <> auth.uid()), 0, 'oficineiro não vê mudança de outra pessoa');
reset role;

select set_config('t.hoje', (privado.hoje() + 12)::text, true);
select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
set local role authenticated;
select is(privado.escola_atual(), (select b from esc), 'na data a nova escola já vale para o oficineiro');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
set local role authenticated;
select is((select escola_id from public.contas_gestao() where nome = 'Oficineiro B'), (select b from esc), 'mudança vencida é aplicada no cadastro');
select set_config('t.hoje', '', true);
select is(public.alterar_escola('00000000-0000-0000-0000-0000000000b1', (select a from esc), privado.hoje() + 5, 'Outro'), 'agendada', 'agenda a volta');
select lives_ok($$select public.cancelar_mudanca_escola('00000000-0000-0000-0000-0000000000b1')$$, 'coordenador cancela a mudança agendada');
select throws_ok($$select public.cancelar_mudanca_escola('00000000-0000-0000-0000-0000000000b1')$$, '22023', null, 'sem mudança agendada não há o que cancelar');
reset role;

select * from finish();
rollback;
