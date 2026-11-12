begin;
create extension if not exists pgtap with schema extensions;
select plan(55);

insert into public.carteiras values ('CS1', 'CS1 - Teste'), ('CS2', 'CS2 - Teste');
insert into public.escolas (sigla, nome, carteira_id, latitude, longitude, raio_m) overriding system value
values ('Aaa', 'Aaa - Escola Teste A', 'CS1', -19.98, -43.85, 80),
       ('Bbb', 'Bbb - Escola Teste B', 'CS2', null, null, 80);
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'gerente@exemplo.test'),
  ('00000000-0000-0000-0000-0000000000a2', 'coord@exemplo.test'),
  ('00000000-0000-0000-0000-0000000000a3', 'analista1@exemplo.test'),
  ('00000000-0000-0000-0000-0000000000a4', 'analista2@exemplo.test'),
  ('00000000-0000-0000-0000-0000000000a5', 'direcao.a@exemplo.test'),
  ('00000000-0000-0000-0000-0000000000a6', 'ofic.a@exemplo.test'),
  ('00000000-0000-0000-0000-0000000000a7', 'ofic.b@exemplo.test'),
  ('00000000-0000-0000-0000-0000000000a8', 'inativo@exemplo.test');
insert into public.perfis (id, nome, papel, escola_id, carteira_id, ativo) values
  ('00000000-0000-0000-0000-0000000000a1', 'Gerente Teste', 'gerente', null, null, true),
  ('00000000-0000-0000-0000-0000000000a2', 'Coord Teste', 'coordenador', null, null, true),
  ('00000000-0000-0000-0000-0000000000a3', 'Analista Um', 'analista', null, 'CS1', true),
  ('00000000-0000-0000-0000-0000000000a4', 'Analista Dois', 'analista', null, 'CS2', true),
  ('00000000-0000-0000-0000-0000000000a5', 'Direcao A', 'direcao', (select id from public.escolas where sigla = 'Aaa'), null, true),
  ('00000000-0000-0000-0000-0000000000a6', 'Oficineiro A', 'oficineiro', (select id from public.escolas where sigla = 'Aaa'), null, true),
  ('00000000-0000-0000-0000-0000000000a7', 'Oficineiro B', 'oficineiro', (select id from public.escolas where sigla = 'Bbb'), null, true),
  ('00000000-0000-0000-0000-0000000000a8', 'Ex Gerente', 'gerente', null, null, false);
update public.perfis set trocar_senha = false;
insert into public.jornada_pessoas (escola_id, nome, tipo, ano_escolar, dias_sem_acesso, dias_acesso, base_ref)
select e.id, x.nome, x.tipo, x.ano, 3, 10, '2026-10-07'
  from (values ('Aaa', 'Aluno Ficticio A', 'A', 4), ('Aaa', 'Prof Ficticio A', 'P', 0), ('Bbb', 'Aluno Ficticio B', 'A', 5)) x(sig, nome, tipo, ano)
  join public.escolas e on e.sigla = x.sig;
insert into public.aulas_registro (oficineiro_id, escola_id, data, inicio, fim, turma, tipo, presentes, matriculados, situacao)
select p.id, p.escola_id, privado.hoje(), '07:00', '07:50', '5º A', 'R', 20, 25, 'Realizada'
  from public.perfis p where p.papel = 'oficineiro';
insert into public.presencas (oficineiro_id, escola_id, data, inicio, fim)
select p.id, p.escola_id, privado.hoje(), (privado.hoje() + time '07:00') at time zone 'America/Sao_Paulo',
       (privado.hoje() + time '12:00') at time zone 'America/Sao_Paulo'
  from public.perfis p where p.papel = 'oficineiro';

create function pg_temp.como(p_uid text, p_aal text default 'aal2') returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
$$;
grant execute on function pg_temp.como(text, text) to authenticated, anon;
select set_config('t.aula_b', (select a.id from public.aulas_registro a join public.perfis p on p.id = a.oficineiro_id where p.nome = 'Oficineiro B')::text, true);

select is((select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity), 0,
          'toda tabela do public tem RLS ligado');
select is((select count(*)::int from information_schema.role_table_grants
            where grantee = 'anon' and table_schema = 'public'), 0,
          'anon não tem nenhuma permissão em tabela');
select is((select count(*)::int from information_schema.role_routine_grants
            where grantee in ('anon', 'PUBLIC') and routine_schema in ('public', 'privado', 'auditoria')), 0,
          'anon/PUBLIC não executam nenhuma função do FSM');

set local role anon;
select throws_ok('select * from public.jornada_pessoas', '42501', null, 'anon: jornada negada');
select throws_ok('select * from public.perfis', '42501', null, 'anon: perfis negados');
select throws_ok($$select public.revelar_cpf(1)$$, '42501', null, 'anon: revelar_cpf negado');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a6', 'aal2');
set local role authenticated;
select is((select count(*)::int from public.jornada_pessoas), 0, 'oficineiro: não vê a Jornada (alunos)');
select is((select count(*)::int from public.aulas_registro), 1, 'oficineiro: vê só as próprias aulas');
select is((select count(*)::int from public.perfis where papel = 'oficineiro'), 1, 'oficineiro: não vê oficineiro de outra escola');
select throws_ok($$update public.aulas_registro set check_direcao = 'ok'$$, '42501', null,
                 'oficineiro: não consegue marcar a própria aula como conferida');
select throws_ok($$update public.perfis set papel = 'gerente'$$, '42501', null, 'oficineiro: não muda o próprio papel');
select lives_ok($$insert into public.aulas_registro (oficineiro_id, escola_id, data, inicio, fim, turma, tipo, presentes, matriculados, situacao)
                 values ('00000000-0000-0000-0000-0000000000a6', (select id from public.escolas where sigla = 'Aaa'),
                         privado.hoje(), '08:40', '09:30', '4º B', 'P', 22, 24, 'Realizada')$$,
                'oficineiro: registra aula própria');
select throws_ok($$insert into public.aulas_registro (oficineiro_id, escola_id, data, inicio, fim, turma, tipo, situacao)
                   values ('00000000-0000-0000-0000-0000000000a7', (select id from public.escolas where sigla = 'Bbb'),
                           privado.hoje(), '10:00', '10:50', '3º A', 'R', 'Realizada')$$, '42501', null,
                 'oficineiro: não registra aula em nome de outro');
select throws_ok($$insert into public.aulas_registro (oficineiro_id, escola_id, data, inicio, fim, turma, tipo, situacao)
                   values ('00000000-0000-0000-0000-0000000000a6', (select id from public.escolas where sigla = 'Aaa'),
                           privado.hoje() - 400, '10:00', '10:50', '3º A', 'R', 'Realizada')$$, '42501', null,
                 'oficineiro: não registra aula em mês já passado');
reset role;
delete from public.presencas;
set local role authenticated;
select is((public.marcar_presenca('entrada', -19.9805, -43.8503, 10) ->> 'aceita')::boolean, true,
          'entrada dentro do raio é aceita');
select is((select count(*)::int from information_schema.columns
            where table_schema = 'public' and table_name = 'presencas' and column_name in ('latitude', 'longitude', 'lat', 'lng')), 0,
          'presença não tem coluna de latitude/longitude');
select throws_ok($$select public.marcar_presenca('entrada', -19.98, -43.85, 10)$$, '22023', null, 'entrada duplicada no dia é recusada');
select throws_ok($$select public.conferir_aula((select min(id) from public.aulas_registro), true)$$, '42501', null,
                 'oficineiro: não confere aula (papel da direção)');
select throws_ok($$select public.importar_os('{}')$$, '42501', null, 'oficineiro: não importa OS');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a7', 'aal2');
set local role authenticated;
select is((public.marcar_presenca('entrada', null, null, null) ->> 'motivo'), 'Sem localização', 'entrada sem GPS é recusada');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a5', 'aal2');
set local role authenticated;
select is((select count(*)::int from public.aulas_registro), 2, 'direção: vê só as aulas da própria escola');
select is((select count(*)::int from public.jornada_pessoas), 0, 'direção: não vê a Jornada (alunos)');
select lives_ok($$select public.conferir_aula((select min(id) from public.aulas_registro), true)$$, 'direção: confere aula da própria escola');
select throws_ok($$select public.conferir_aula(999999, true)$$, '42501', null, 'direção: aula inexistente é negada');
select throws_ok(format('select public.conferir_aula(%s, true)', current_setting('t.aula_b')),
                 '42501', null, 'direção: não confere aula de outra escola');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a6', 'aal2');
set local role authenticated;
update public.aulas_registro set presentes = 1 where check_direcao = 'ok';
select is((select count(*)::int from public.aulas_registro where check_direcao = 'ok' and presentes = 1), 0,
          'oficineiro: aula confirmada pela direção não muda');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a3', 'aal1');
set local role authenticated;
select is((select count(*)::int from public.jornada_pessoas), 0, 'analista sem MFA (aal1): não vê nada da Jornada');
select is((select count(*)::int from public.escolas), 0, 'analista sem MFA (aal1): não vê nem as escolas');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000000a3', 'aal2');
set local role authenticated;
select is((select count(*)::int from public.jornada_pessoas), 2, 'analista CS1 com MFA: vê só a Jornada da sua carteira');
select is((select count(*)::int from public.aulas_registro), 2, 'analista CS1: vê só aulas da carteira');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a1', 'aal1');
set local role authenticated;
select throws_ok($$select public.importar_os('{"numero":"1","secretaria":"SEMED","linhas":[]}')$$, '42501', null,
                 'gerente sem MFA: não importa OS');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000000a1', 'aal2');
set local role authenticated;
select is((public.importar_os('{"numero":"17","secretaria":"SEMED","arquivo":"teste.xlsx","recebida_em":"2026-10-01","linhas":[
            {"seq":"1","nome":"Pessoa Ficticia Um","email":"um@exemplo.test","cpf":"529.982.247-25","matricula":"1","cargo":"Professor","escola_sigla":"Aaa","carteira_id":"CS1"},
            {"seq":"2","nome":"Pessoa Ficticia Dois","email":"dois@exemplo.test","cpf":"11144477735","matricula":"2","cargo":"Supervisor","escola_sigla":"Bbb","carteira_id":"CS2"},
            {"seq":"3","nome":"CPF Invalido","cpf":"12345678900"},
            {"seq":"4","nome":"Repetido","cpf":"52998224725"}]}') ->> 'inseridos')::int, 2,
          'importar_os: insere só CPFs válidos e não repetidos');
select is((select cpf_mascara from public.onboarding_itens where nome = 'Pessoa Ficticia Um'), '***.982.247-**', 'CPF guardado mascarado para exibição');
select throws_ok($$select cpf_cifrado from public.onboarding_itens$$, '42501', null, 'gerente: nem o gerente lê a coluna cifrada direto');
select is(public.revelar_cpf((select id from public.onboarding_itens where nome = 'Pessoa Ficticia Um')), '52998224725',
          'gerente com MFA: revela CPF pela função');
reset role;
select is((select count(*)::int from auditoria.eventos where acao = 'REVELAR_CPF'), 1, 'revelar CPF ficou na auditoria');
select is((select count(*)::int from auditoria.eventos where detalhes::text like '%52998224725%' or detalhes::text like '%11144477735%'), 0,
          'auditoria não guarda CPF aberto');
select is((select count(*)::int from public.onboarding_itens where position('52998224725'::bytea in cpf_cifrado) > 0), 0,
          'CPF não está em texto puro no banco');

select set_config('t.item_cs2', (select id from public.onboarding_itens where nome = 'Pessoa Ficticia Dois')::text, true);
select pg_temp.como('00000000-0000-0000-0000-0000000000a3', 'aal2');
set local role authenticated;
select is((select count(*)::int from public.onboarding_itens), 1, 'analista CS1: vê só as pendências da carteira');
select throws_ok(format('select public.revelar_cpf(%s)', (select min(id) from public.onboarding_itens)), '42501', null,
                 'analista: não revela CPF');
select throws_ok(format('select public.dar_baixa_onboarding(%s, current_date, %L)', current_setting('t.item_cs2'), 'Presencial'), '42501', null,
                 'analista: não dá baixa em item de outra carteira');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a8', 'aal2');
set local role authenticated;
select is((select count(*)::int from public.escolas), 0, 'perfil desativado: não vê nada');
select throws_ok($$select public.revelar_cpf(1)$$, '42501', null, 'perfil desativado: não revela CPF');
reset role;
select throws_ok($$delete from auditoria.eventos$$, '42501', null, 'auditoria: nem o administrador apaga');
select throws_ok($$update auditoria.eventos set acao = 'x'$$, '42501', null, 'auditoria: nem o administrador altera');

select pg_temp.como('00000000-0000-0000-0000-0000000000a1', 'aal2');
set local role authenticated;
select throws_ok($$select * from auditoria.eventos$$, '42501', null, 'gerente: auditoria só pela função (sem acesso direto)');
select ok((select count(*) from public.auditoria_recente(50)) > 0, 'gerente com MFA: lê a auditoria pela função');
reset role;


select pg_temp.como('00000000-0000-0000-0000-0000000000a6', 'aal1');
set local role authenticated;
select is((select count(*)::int from public.aulas_registro), 0, 'oficineiro sem MFA (aal1): não vê nada');
reset role;
select is(public.fsm_definir_cpf('00000000-0000-0000-0000-0000000000a6', '529.982.247-25'), '***.982.247-**', 'CPF de conta gravado cifrado, devolve só a máscara');
select is((select count(*)::int from public.fsm_conta_por_cpf('52998224725')), 1, 'conta encontrada pelo CPF (só service_role)');
select throws_ok($$select public.fsm_definir_cpf('00000000-0000-0000-0000-0000000000a7', '52998224725')$$, '23505', null, 'mesmo CPF não pode ir para duas contas');
select pg_temp.como('00000000-0000-0000-0000-0000000000a6', 'aal2');
set local role authenticated;
select throws_ok($$select cpf_cifrado from public.perfis$$, '42501', null, 'CPF cifrado do perfil é ilegível pela API');
select throws_ok($$select * from public.fsm_conta_por_cpf('52998224725')$$, '42501', null, 'usuário logado não consegue procurar conta por CPF');
select throws_ok($$select public.fsm_tentativa('x', 5, 60)$$, '42501', null, 'usuário logado não mexe no limite de tentativas');
reset role;
set local role anon;
select throws_ok($$select * from public.fsm_conta_por_usuario('teste')$$, '42501', null, 'anon não consegue procurar conta por usuário');
reset role;

select * from finish();
rollback;
