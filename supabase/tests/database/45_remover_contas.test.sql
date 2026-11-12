begin;
create extension if not exists pgtap with schema extensions;
select plan(20);

insert into public.carteiras values ('CR1', 'CR1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Rmv', 'Rmv - Escola R', 'CR1');
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000000f1', 'sem.registros@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000f2', 'com.registros@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000f3', 'antiga@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000f4', 'recente@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000f5', 'admin@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, escola_id, usuario, telefone, cpf_mascara, cpf_hash) values
  ('00000000-0000-0000-0000-0000000000f1', 'Pessoa Sem Registros', 'direcao', (select id from public.escolas where sigla = 'Rmv'), 'direcao.sem', '31999990001', '***.111.111-**', '\x01'),
  ('00000000-0000-0000-0000-0000000000f2', 'Pessoa Com Registros', 'oficineiro', (select id from public.escolas where sigla = 'Rmv'), 'oficineiro.com', '31999990002', '***.222.222-**', '\x02'),
  ('00000000-0000-0000-0000-0000000000f3', 'Pessoa Antiga', 'oficineiro', (select id from public.escolas where sigla = 'Rmv'), 'oficineiro.antiga', null, null, null),
  ('00000000-0000-0000-0000-0000000000f4', 'Pessoa Recente', 'oficineiro', (select id from public.escolas where sigla = 'Rmv'), 'oficineiro.recente', null, null, null);
insert into public.perfis (id, nome, papel) values ('00000000-0000-0000-0000-0000000000f5', 'Administrador Teste', 'administrador');
insert into public.presenca_tentativas (oficineiro_id, tipo, motivo) values
  ('00000000-0000-0000-0000-0000000000f2', 'entrada', 'teste'),
  ('00000000-0000-0000-0000-0000000000f3', 'entrada', 'teste');

update public.perfis set ativo = false where id = '00000000-0000-0000-0000-0000000000f4';
select ok((select desativado_em is not null from public.perfis where id = '00000000-0000-0000-0000-0000000000f4'), 'desativar marca a data');
update public.perfis set ativo = true where id = '00000000-0000-0000-0000-0000000000f4';
select ok((select desativado_em is null from public.perfis where id = '00000000-0000-0000-0000-0000000000f4'), 'reativar limpa a data');
update public.perfis set ativo = false where id in ('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000f4');
update public.perfis set desativado_em = now() - interval '31 days' where id = '00000000-0000-0000-0000-0000000000f3';
update public.perfis set desativado_em = now() - interval '29 days' where id = '00000000-0000-0000-0000-0000000000f4';

select ok(not has_function_privilege('authenticated', 'public.remover_conta(uuid, uuid, text)', 'EXECUTE'), 'usuário comum não chama a remoção');
select ok(not has_function_privilege('anon', 'public.remover_conta(uuid, uuid, text)', 'EXECUTE'), 'visitante não chama a remoção');
select ok(has_function_privilege('service_role', 'public.remover_conta(uuid, uuid, text)', 'EXECUTE'), 'função de contas chama a remoção');
select ok(not has_function_privilege('authenticated', 'privado.remover_contas_desativadas()', 'EXECUTE'), 'limpeza automática não é chamada pelo site');

set local role service_role;
select is(public.remover_conta('00000000-0000-0000-0000-0000000000f5', '00000000-0000-0000-0000-0000000000f1', 'Conta criada por engano'),
          '{"login": "limpo", "resultado": "apagada"}'::jsonb, 'sem registros: apaga tudo');
select is(public.remover_conta('00000000-0000-0000-0000-0000000000f5', '00000000-0000-0000-0000-0000000000f2', 'Saiu do projeto'),
          '{"login": "limpo", "resultado": "anonimizada"}'::jsonb, 'com registros: mantém o histórico anônimo');
select throws_ok($$ select public.remover_conta('00000000-0000-0000-0000-0000000000f5', '00000000-0000-0000-0000-0000000000f5', 'Teste de bloqueio') $$,
                 '42501', null, 'conta de administrador não é apagada');
select throws_ok($$ select public.remover_conta('00000000-0000-0000-0000-0000000000f5', '00000000-0000-0000-0000-0000000000ff', 'Conta inexistente') $$,
                 '22023', null, 'conta inexistente é recusada');
reset role;

select ok(not exists (select 1 from public.perfis where id = '00000000-0000-0000-0000-0000000000f1'), 'perfil sem registros removido');
select ok(not exists (select 1 from auth.users where id = '00000000-0000-0000-0000-0000000000f1'), 'login sem registros removido');
select is((select nome from public.perfis where id = '00000000-0000-0000-0000-0000000000f2'), 'Conta removida', 'nome substituído');
select ok((select usuario is null and telefone is null and cpf_mascara is null and cpf_hash is null and not ativo and removido_em is not null
             from public.perfis where id = '00000000-0000-0000-0000-0000000000f2'), 'dados pessoais apagados');
select is((select count(*)::int from public.presenca_tentativas where oficineiro_id = '00000000-0000-0000-0000-0000000000f2'), 1, 'registros mantidos');
select ok((select email like 'removida.%@conta.invalid' from auth.users where id = '00000000-0000-0000-0000-0000000000f2'), 'e-mail do login substituído');
select ok(exists (select 1 from auditoria.eventos where acao = 'REMOVER_CONTA' and registro = '00000000-0000-0000-0000-0000000000f2'), 'remoção fica na auditoria');

select is(privado.remover_contas_desativadas(), 1, 'limpeza automática remove só a desativada há mais de 30 dias');
select is((select nome from public.perfis where id = '00000000-0000-0000-0000-0000000000f3'), 'Conta removida', 'desativada há 31 dias foi removida');
select is((select nome from public.perfis where id = '00000000-0000-0000-0000-0000000000f4'), 'Pessoa Recente', 'desativada há 29 dias continua');

select * from finish();
rollback;
