begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Aaa', 'Aaa - Escola Teste', 'CS1');
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000000d1', 'ofic.um@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000d2', 'ofic.dois@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha)
select x.id::uuid, x.nome, 'oficineiro', e.id, x.usuario, false
  from (values ('00000000-0000-0000-0000-0000000000d1', 'Oficineiro Um', 'ofic.um'),
               ('00000000-0000-0000-0000-0000000000d2', 'Oficineiro Dois', 'ofic.dois')) x(id, nome, usuario)
  cross join public.escolas e where e.sigla = 'Aaa';
select public.fsm_definir_cpf('00000000-0000-0000-0000-0000000000d2', '52998224725');
insert into public.jornada_pessoas (escola_id, nome, tipo, ano_escolar, dias_sem_acesso, dias_acesso, base_ref)
select e.id, 'Aluno Ficticio', 'A', 4, 3, 10, '2026-10-07' from public.escolas e where e.sigla = 'Aaa';
insert into public.presencas (oficineiro_id, escola_id, data, inicio, fim)
select p.id, p.escola_id, privado.hoje(), (privado.hoje() + time '07:00') at time zone 'America/Sao_Paulo',
       (privado.hoje() + time '12:00') at time zone 'America/Sao_Paulo'
  from public.perfis p where p.id = '00000000-0000-0000-0000-0000000000d1';

create function pg_temp.como(p_uid text, p_aal text default 'aal2') returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
$$;
grant execute on function pg_temp.como(text, text) to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000000d1', 'aal1');
set local role authenticated;
select throws_ok($$insert into public.aulas_registro (oficineiro_id, escola_id, data, inicio, fim, turma, tipo, presentes, matriculados, situacao)
  values ('00000000-0000-0000-0000-0000000000d1', (select privado.escola_atual()), privado.hoje(), '07:00', '07:50', '5º A', 'R', 20, 25, 'Realizada')$$,
  '42501', null, 'sem o autenticador, o oficineiro não registra aula');
select is((select count(*)::int from public.perfis), 0, 'sem o autenticador, não vê nem o próprio perfil');
select ok(public.meu_acesso() ->> 'nome' is null, 'sem o autenticador, o nome não é revelado');
select ok(public.meu_acesso() ->> 'escola_id' is null, 'sem o autenticador, a escola não é revelada');
select is(public.meu_acesso() ->> 'papel', 'oficineiro', 'sem o autenticador, o papel continua disponível para o site');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000d1', 'aal2');
set local role authenticated;
select lives_ok($$insert into public.aulas_registro (oficineiro_id, escola_id, data, inicio, fim, turma, tipo, presentes, matriculados, situacao)
  values ('00000000-0000-0000-0000-0000000000d1', (select privado.escola_atual()), privado.hoje(), '07:00', '07:50', '5º A', 'R', 20, 25, 'Realizada')$$,
  'com o autenticador, o oficineiro registra aula');
select is(public.meu_acesso() ->> 'nome', 'Oficineiro Um', 'com o autenticador, o nome aparece');
select is((select count(*)::int from public.perfis), 2, 'com o autenticador, vê os colegas da escola');
select throws_ok($$select usuario from public.perfis$$, '42501', null, 'não lê o nome de usuário de ninguém');
select throws_ok($$select cpf_mascara from public.perfis$$, '42501', null, 'não lê o CPF mascarado de ninguém');
select throws_ok($$select trocar_senha from public.perfis$$, '42501', null, 'não lê quem ainda não ativou a conta');
select throws_ok($$select cpf_hash from public.perfis$$, '42501', null, 'não lê o hash do CPF');
reset role;

select ok(not has_function_privilege('authenticated', 'public.fsm_conta_por_cpf(text)', 'execute')
      and not has_function_privilege('authenticated', 'public.fsm_conta_por_usuario(text)', 'execute')
      and not has_function_privilege('authenticated', 'public.fsm_definir_cpf(uuid, text)', 'execute')
      and not has_function_privilege('authenticated', 'public.fsm_tentativa(text, integer, integer)', 'execute')
      and not has_function_privilege('authenticated', 'public.fsm_tentativa_zerar(text)', 'execute')
      and not has_function_privilege('authenticated', 'public.registrar_acao_admin(uuid, text, text, jsonb)', 'execute'),
   'funções exclusivas do servidor não são executáveis por usuário logado');
select ok(not has_function_privilege('authenticated', 'privado.cpf_decifrar(bytea)', 'execute')
      and not has_function_privilege('authenticated', 'privado.cpf_cifrar(text)', 'execute')
      and not has_function_privilege('authenticated', 'privado.segredo(text)', 'execute'),
   'funções de criptografia não são executáveis por usuário logado');

update public.jornada_pessoas set dias_sem_acesso = 4;
select is((select count(*)::int from auditoria.eventos where acao = 'CARGA_UPDATE' and tabela = 'jornada_pessoas'), 1, 'alteração na jornada fica registrada na auditoria');
select is((select count(*)::int from auditoria.eventos where detalhes::text like '%52998224725%'), 0, 'o CPF nunca aparece na auditoria');

select * from finish();
rollback;
