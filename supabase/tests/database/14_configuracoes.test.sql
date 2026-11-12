begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id, raio_m) values ('Aaa', 'Aaa - Escola A', 'CS1', 150);
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000000a1', 'of.a@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000a2', 'of.b@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000000a1', 'Oficineiro A', 'oficineiro', (select id from public.escolas), 'of.a', false),
  ('00000000-0000-0000-0000-0000000000a2', 'Oficineiro B', 'oficineiro', (select id from public.escolas), 'of.b', false);
select public.fsm_definir_cpf('00000000-0000-0000-0000-0000000000a1', '52998224725');
create function pg_temp.como(p_uid text, p_aal text default 'aal2') returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
$$;
grant execute on function pg_temp.como(text, text) to authenticated;

create temp table base_aud as select count(*)::int n from auditoria.eventos;
set local role anon;
select throws_ok($$select public.minha_conta()$$, '42501', null, 'sem login não lê dados da conta');
select throws_ok($$select public.salvar_preferencias('{"tema": "escuro"}')$$, '42501', null, 'sem login não salva preferências');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a1', 'aal1');
set local role authenticated;
select throws_ok($$select public.minha_conta()$$, '42501', null, 'sem autenticador não lê dados da conta');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
select is((public.minha_conta() ->> 'usuario'), 'of.a', 'conta mostra o usuário');
select is((public.minha_conta() -> 'escola' ->> 'sigla'), 'Aaa', 'conta mostra a escola');
select ok((public.minha_conta() - 'acesso_anterior')::text !~ '529|998|224|725|cpf' and public.minha_conta()::text !~ '52998224725|529\.982|982\.247|224-?725|cpf', 'dados da conta não trazem CPF');
select is(public.minhas_preferencias(), '{}'::jsonb, 'sem preferências salvas');
select is(public.salvar_preferencias('{"tema": "escuro", "texto": "grande"}'), '{"tema": "escuro", "texto": "grande"}'::jsonb, 'salva tema e texto');
select is(public.salvar_preferencias('{"animacoes": "reduzir"}') ->> 'tema', 'escuro', 'salvar uma preferência mantém as outras');
select throws_ok($$select public.salvar_preferencias('{"tema": "roxo"}')$$, '22023', null, 'valor fora da lista é recusado');
select throws_ok($$select public.salvar_preferencias('{"cor": "azul"}')$$, '22023', null, 'chave desconhecida é recusada');
select throws_ok($$select public.salvar_preferencias('{"tema": ["escuro"]}')$$, '22023', null, 'valor que não é texto é recusado');
select throws_ok($$select * from privado.conta_extras$$, '42501', null, 'tabela das preferências não é lida direto');
select throws_ok($$select public.fsm_registrar_login('00000000-0000-0000-0000-0000000000a1')$$, '42501', null, 'usuário não registra o próprio login');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a2');
set local role authenticated;
select is(public.minhas_preferencias(), '{}'::jsonb, 'preferências de um não aparecem para outro');
reset role;

select public.fsm_registrar_login('00000000-0000-0000-0000-0000000000a1');
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
select is((public.minha_conta() ->> 'acesso_anterior'), null, 'primeiro login não tem acesso anterior');
reset role;
update privado.conta_extras set acesso_atual = now() - interval '1 day' where usuario_id = '00000000-0000-0000-0000-0000000000a1';
select public.fsm_registrar_login('00000000-0000-0000-0000-0000000000a1');
select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
select ok((public.minha_conta() ->> 'acesso_anterior')::timestamptz < now() - interval '23 hours', 'segundo login guarda o anterior');
reset role;
select is((select count(*)::int from auditoria.eventos) - (select n from base_aud), 0, 'preferências e logins não enchem a auditoria');

select * from finish();
rollback;
