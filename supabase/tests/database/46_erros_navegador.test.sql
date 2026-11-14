begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000e1', 'erro.gerente@exemplo.test'),
  ('00000000-0000-0000-0000-0000000000e2', 'erro.admin@exemplo.test');
insert into public.perfis (id, nome, papel, trocar_senha) values
  ('00000000-0000-0000-0000-0000000000e1', 'Pessoa Erro', 'gerente', false),
  ('00000000-0000-0000-0000-0000000000e2', 'Administrador Erro', 'administrador', false);

create function pg_temp.como(p_uid uuid, p_aal text default 'aal2') returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
$$;

select ok(not has_function_privilege('anon', 'public.registrar_erro_navegador(text, text, text, integer, integer, text, text)', 'EXECUTE'),
          'visitante não registra erro');
select ok(not has_function_privilege('authenticated', 'privado.limpar_erros_navegador()', 'EXECUTE'), 'limpeza não é chamada pelo site');
select ok(not has_table_privilege('authenticated', 'public.erros_navegador', 'SELECT'), 'tabela não é lida diretamente');
select ok(not has_table_privilege('authenticated', 'public.erros_navegador', 'INSERT'), 'tabela não recebe gravação direta');

select pg_temp.como('00000000-0000-0000-0000-0000000000e1', 'aal1');
set local role authenticated;
select is(public.registrar_erro_navegador('TypeError: x is undefined' || chr(10) || 'linha 2', 'oficineiro/presenca', 'app.js', 12, 4, 'Navegador de teste', '1.1.0'),
          true, 'erro registrado mesmo antes do MFA');
select is(public.registrar_erro_navegador('TypeError: x is undefined' || chr(10) || 'linha 2', 'oficineiro/presenca', 'app.js', 12, 4, 'Navegador de teste', '1.1.0'),
          false, 'erro repetido em 10 minutos é ignorado');
select is(public.registrar_erro_navegador('   ', 'oficineiro/presenca', null, null, null, null, null), false, 'mensagem vazia é ignorada');
select is(public.registrar_erro_navegador(repeat('a', 900), repeat('p', 400), repeat('o', 400), -5, 99999999, repeat('n', 400), repeat('v', 40)),
          true, 'campos longos são aceitos');
select throws_ok($$ select * from public.admin_erros_navegador(10) $$, '42501', null, 'gerente não lê os erros');
select throws_ok($$ select count(*) from public.erros_navegador $$, '42501', null, 'gerente não lê a tabela');
reset role;

select is((select mensagem from public.erros_navegador where linha = 12), 'TypeError: x is undefined linha 2', 'quebras de linha viram espaço');
select ok((select length(mensagem) = 500 and length(pagina) = 200 and length(origem) = 300 and length(navegador) = 200 and length(versao) = 20
                  and linha is null and coluna is null
             from public.erros_navegador where mensagem like 'aaa%'), 'tamanhos e números fora do intervalo são limitados');
select is((select papel from public.erros_navegador where linha = 12), 'gerente', 'papel gravado com o erro');

insert into public.erros_navegador (usuario_id, pagina, mensagem)
select '00000000-0000-0000-0000-0000000000e1', 'teste', 'erro ' || n from generate_series(1, 30) n;
select pg_temp.como('00000000-0000-0000-0000-0000000000e1');
set local role authenticated;
select is(public.registrar_erro_navegador('outro erro', 'teste', null, null, null, null, null), false, 'mais de 30 por hora são ignorados');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000e2');
set local role authenticated;
select is((select count(*)::int from public.admin_erros_navegador(1000) where nome = 'Pessoa Erro'), 32, 'Administrador lê os erros com o nome');
reset role;

update public.erros_navegador set em = now() - interval '91 days' where mensagem like 'erro %';
select is(privado.limpar_erros_navegador(), 30, 'limpeza apaga os registros com mais de 90 dias');

select * from finish();
rollback;
