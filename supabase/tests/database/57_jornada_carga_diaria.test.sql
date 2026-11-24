begin;
create extension if not exists pgtap with schema extensions;
select plan(40);

insert into public.carteiras values ('JC1', 'JC1 - Teste'), ('JC2', 'JC2 - Teste') on conflict do nothing;
insert into public.escolas (sigla, nome, carteira_id) values
  ('Jca', 'Jca - Escola Carga A', 'JC1'),
  ('Jcb', 'Jcb - Escola Carga B', 'JC2');
insert into public.escolas (sigla, nome) values ('Jcs', 'Jcs - Unidade Sem Carteira');
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000b1a01', 'jc.admin@exemplo.test'),
  ('00000000-0000-0000-0000-0000000b1a02', 'jc.coord@exemplo.test'),
  ('00000000-0000-0000-0000-0000000b1a03', 'jc.gerente@exemplo.test'),
  ('00000000-0000-0000-0000-0000000b1a04', 'jc.analista@exemplo.test'),
  ('00000000-0000-0000-0000-0000000b1a05', 'jc.direcao@exemplo.test');
insert into public.perfis (id, nome, papel, escola_id, carteira_id, trocar_senha) values
  ('00000000-0000-0000-0000-0000000b1a01', 'Admin Carga', 'administrador', null, null, false),
  ('00000000-0000-0000-0000-0000000b1a02', 'Coord Carga', 'coordenador', null, null, false),
  ('00000000-0000-0000-0000-0000000b1a03', 'Gerente Carga', 'gerente', null, null, false),
  ('00000000-0000-0000-0000-0000000b1a04', 'Analista Carga', 'analista', null, 'JC1', false),
  ('00000000-0000-0000-0000-0000000b1a05', 'Direcao Carga', 'direcao', (select id from public.escolas where sigla = 'Jca'), null, false);

create function pg_temp.como(p_uid text, p_aal text default 'aal2') returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
$$;
grant execute on function pg_temp.como(text, text) to authenticated;
create function pg_temp.esc(p_sigla text) returns smallint language sql as $$
  select id from public.escolas where sigla = p_sigla;
$$;
grant execute on function pg_temp.esc(text) to authenticated;
create function pg_temp.h(p_login text) returns text language sql as $$
  select encode(extensions.digest(p_login, 'sha256'), 'hex');
$$;
grant execute on function pg_temp.h(text) to authenticated;
create function pg_temp.pessoas(p_escola_a smallint, p_escola_b smallint) returns jsonb language sql as $$
  select jsonb_build_array(
    jsonb_build_object('h', pg_temp.h('login.um'), 'nome', 'Aluno Um', 'tipo', 'A', 'escola', p_escola_a, 'carteira', 'JC1',
                       'turma', '9º A', 'ano', 9, 'responsavel', 'Professora Turma', 'primeiro', '2026-03-01',
                       'ultimo', '2026-11-20', 'dias', 40),
    jsonb_build_object('h', pg_temp.h('login.dois'), 'nome', 'Professor Dois', 'tipo', 'P', 'escola', p_escola_a, 'carteira', 'JC1',
                       'primeiro', '2026-02-01', 'ultimo', '2026-09-01', 'dias', 90),
    jsonb_build_object('h', pg_temp.h('login.tres'), 'nome', 'Servidor Tres', 'tipo', 'S', 'escola', p_escola_b, 'carteira', 'JC2'),
    jsonb_build_object('h', pg_temp.h('login.quatro'), 'nome', 'Servidor Quatro', 'tipo', 'S', 'unidade', 'Secretaria de Teste da Carga',
                       'carteira', 'AT1', 'ultimo', '2026-11-10', 'dias', 3)
  );
$$;
grant execute on function pg_temp.pessoas(smallint, smallint) to authenticated;
create function pg_temp.unidades(p_sem_carteira smallint) returns jsonb language sql as $$
  select jsonb_build_array(
    jsonb_build_object('nome', 'Secretaria de Teste da Carga', 'carteira', 'AT1'),
    jsonb_build_object('escola', p_sem_carteira, 'carteira', 'AT1')
  );
$$;
grant execute on function pg_temp.unidades(smallint) to authenticated;

select ok(not has_table_privilege('authenticated', 'public.jornada_pessoas', 'INSERT'), 'base de acessos sem gravação direta');
select ok(not has_table_privilege('authenticated', 'public.jornada_retratos', 'INSERT'), 'retratos sem gravação direta');
select ok(not has_column_privilege('authenticated', 'public.jornada_pessoas', 'login_hash', 'SELECT'), 'resumo do login não é lido pelo site');
select ok(has_column_privilege('authenticated', 'public.jornada_pessoas', 'ultimo_acesso', 'SELECT'), 'datas de acesso podem ser lidas');
select ok(not has_function_privilege('anon', 'public.carregar_base_acessos(date, jsonb, jsonb, boolean, jsonb)', 'EXECUTE'),
          'visitante não carrega a base');
select is((select count(*)::int from information_schema.columns
            where table_schema = 'public' and table_name = 'jornada_pessoas'
              and column_name in ('email', 'matricula', 'sag_id', 'imagem', 'login', 'cpf')), 0,
          'a base não tem colunas de e-mail, matrícula, identificador externo, imagem ou login aberto');

set local role authenticated;
select pg_temp.como('00000000-0000-0000-0000-0000000b1a02');
select throws_ok($$ select public.carregar_base_acessos(date '2026-11-21', null, pg_temp.pessoas(pg_temp.esc('Jca'), pg_temp.esc('Jcb'))) $$,
                 '42501', null, 'coordenador não carrega a base');
select pg_temp.como('00000000-0000-0000-0000-0000000b1a03');
select throws_ok($$ select public.carregar_base_acessos(date '2026-11-21', null, pg_temp.pessoas(pg_temp.esc('Jca'), pg_temp.esc('Jcb'))) $$,
                 '42501', null, 'gerente não carrega a base');
select pg_temp.como('00000000-0000-0000-0000-0000000b1a01', 'aal1');
select throws_ok($$ select public.carregar_base_acessos(date '2026-11-21', null, pg_temp.pessoas(pg_temp.esc('Jca'), pg_temp.esc('Jcb'))) $$,
                 '42501', null, 'administrador sem MFA não carrega a base');

select pg_temp.como('00000000-0000-0000-0000-0000000b1a01');
select throws_ok($$ select public.carregar_base_acessos(privado.hoje() + 1, pg_temp.unidades(pg_temp.esc('Jcs')),
                    pg_temp.pessoas(pg_temp.esc('Jca'), pg_temp.esc('Jcb'))) $$, '22023', null, 'data futura recusada');
select throws_ok($$ select public.carregar_base_acessos(date '2026-11-21', null, '[]'::jsonb) $$, '22023', null, 'carga vazia recusada');
select throws_ok($$ select public.carregar_base_acessos(date '2026-11-21', null, pg_temp.pessoas(pg_temp.esc('Jca'), pg_temp.esc('Jcb'))) $$,
                 '22023', 'pessoa 4: unidade não encontrada', 'pessoa de unidade desconhecida recusada');
select throws_ok($$ select public.carregar_base_acessos(date '2026-11-21', null,
                    jsonb_build_array(jsonb_build_object('h', 'abc', 'nome', 'Fulano', 'tipo', 'A', 'escola', pg_temp.esc('Jca')))) $$,
                 '22023', 'pessoa 1: login sem resumo válido', 'login sem resumo recusado');
select throws_ok($$ select public.carregar_base_acessos(date '2026-11-21', null,
                    jsonb_build_array(jsonb_build_object('h', pg_temp.h('x'), 'nome', 'Fulano', 'tipo', 'X', 'escola', pg_temp.esc('Jca')))) $$,
                 '22023', 'pessoa 1: perfil inválido', 'perfil inválido recusado');
select throws_ok($$ select public.carregar_base_acessos(date '2026-11-21', null,
                    jsonb_build_array(jsonb_build_object('h', pg_temp.h('x'), 'nome', 'Fulano', 'tipo', 'A', 'escola', pg_temp.esc('Jca'),
                                                        'ultimo', '2026-11-22'))) $$,
                 '22023', 'pessoa 1: data de acesso depois da data da base', 'acesso depois da base recusado');
select throws_ok($$ select public.carregar_base_acessos(date '2026-11-21', null,
                    jsonb_build_array(jsonb_build_object('h', pg_temp.h('x'), 'nome', 'Fulano', 'tipo', 'A', 'escola', pg_temp.esc('Jca')),
                                      jsonb_build_object('h', pg_temp.h('x'), 'nome', 'Fulano Dois', 'tipo', 'A', 'escola', pg_temp.esc('Jca')))) $$,
                 '22023', 'há logins repetidos na carga', 'login repetido recusado');
select throws_ok($$ select public.carregar_base_acessos(date '2026-11-21', jsonb_build_array(jsonb_build_object('nome', 'Unidade Qualquer', 'carteira', 'ZZ9')),
                    pg_temp.pessoas(pg_temp.esc('Jca'), pg_temp.esc('Jcb'))) $$,
                 '22023', 'unidade 1: carteira não encontrada', 'unidade com carteira inexistente recusada');

select is(public.carregar_base_acessos(date '2026-11-21', pg_temp.unidades(pg_temp.esc('Jcs')),
                                       pg_temp.pessoas(pg_temp.esc('Jca'), pg_temp.esc('Jcb')), false,
                                       '{"arquivos": 7}'::jsonb) - 'base_ref',
          '{"pessoas": 4, "substituidas": 0, "unidades_novas": 1, "unidades_com_carteira": 1}'::jsonb,
          'administrador com MFA carrega a base');
reset role;

select is((select carteira_id from public.escolas where nome = 'Secretaria de Teste da Carga'), 'AT1', 'unidade nova cadastrada com carteira AT1');
select is((select sigla from public.escolas where nome = 'Secretaria de Teste da Carga'), 'Tc', 'sigla da unidade nova gerada pelo nome');
select is((select carteira_id from public.escolas where sigla = 'Jcs'), 'AT1', 'unidade sem carteira recebe a carteira AT1');
select is((select dias_sem_acesso from public.jornada_pessoas where nome = 'Aluno Um'), 1, 'dias sem acesso calculados pela data da base');
select is((select dias_sem_acesso from public.jornada_pessoas where nome = 'Servidor Tres'), -1, 'sem último acesso conta como nunca acessou');
select is((select turma || ' ' || ano_escolar || ' ' || carteira_id from public.jornada_pessoas where nome = 'Aluno Um'), '9º A 9 JC1',
          'turma, ano e carteira gravados');
select is((select dias_acesso from public.jornada_pessoas where nome = 'Servidor Tres'), null, 'dias de acesso desconhecidos ficam vazios');
select ok((select login_hash <> extensions.digest('login.um', 'sha256') and octet_length(login_hash) = 32
             from public.jornada_pessoas where nome = 'Aluno Um'), 'login guardado só como resumo com chave');
select is((select pessoas || ' ' || origem || ' ' || autor_nome || ' ' || (resumo ->> 'arquivos') from public.jornada_retratos
            where base_ref = '2026-11-21'), '4 site Admin Carga 7', 'retrato do dia registrado com autor e resumo');
select is((select count(*)::int from auditoria.eventos where acao = 'CARGA_BASE_ACESSOS' and registro = '2026-11-21'), 1,
          'carga registrada na auditoria');

set local role authenticated;
select pg_temp.como('00000000-0000-0000-0000-0000000b1a01');
select throws_ok($$ select public.carregar_base_acessos(date '2026-11-21', null, pg_temp.pessoas(pg_temp.esc('Jca'), pg_temp.esc('Jcb'))) $$,
                 '22023', 'já existe base de acessos nesta data: confirme a substituição', 'mesma data exige confirmação');
select is(public.carregar_base_acessos(date '2026-11-21', null, pg_temp.pessoas(pg_temp.esc('Jca'), pg_temp.esc('Jcb')), true) ->> 'substituidas',
          '4', 'substituição troca o retrato do dia');
select is(public.carregar_base_acessos(date '2026-10-30', null,
            jsonb_build_array(jsonb_build_object('h', pg_temp.h('login.um'), 'nome', 'Aluno Um', 'tipo', 'A', 'escola', pg_temp.esc('Jca'),
                                                 'ultimo', '2026-10-01', 'dias', 10))) ->> 'pessoas',
          '1', 'retrato de outro dia guardado à parte');
reset role;
select is((select count(*)::int from public.jornada_pessoas where base_ref = '2026-11-21'), 4, 'o retrato substituído não duplica pessoas');
select is((select count(*)::int from public.escolas where nome = 'Secretaria de Teste da Carga'), 1, 'unidade já cadastrada é reaproveitada');

set local role authenticated;
select pg_temp.como('00000000-0000-0000-0000-0000000b1a04');
select is((select count(*)::int from public.jornada_pessoas where base_ref = '2026-11-21'), 2, 'analista vê só a base da sua carteira');
select is((select string_agg(base_ref::text, ',' order by base_ref) from public.jornada_retratos
            where base_ref in ('2026-10-30', '2026-11-21')), '2026-10-30,2026-11-21', 'analista vê as datas dos retratos');
select is((select sum(n)::int || '/' || sum(en)::int from public.jornada_resumo_mensal() where escola_id = pg_temp.esc('Jca')), '3/1',
          'resumo mensal usa o último retrato de cada mês e respeita a carteira');
select is((select count(*)::int from public.jornada_resumo_mensal() where escola_id = pg_temp.esc('Jcb')), 0,
          'resumo mensal não mostra outra carteira');
select pg_temp.como('00000000-0000-0000-0000-0000000b1a04', 'aal1');
select is((select count(*)::int from public.jornada_retratos), 0, 'sem MFA não vê os retratos');
select pg_temp.como('00000000-0000-0000-0000-0000000b1a05');
select is((select count(*)::int from public.jornada_retratos), 0, 'direção não vê os retratos');
reset role;

delete from public.jornada_pessoas where base_ref = '2026-10-30';
select is((select count(*)::int from public.jornada_retratos where base_ref = '2026-10-30'), 0, 'retrato some quando a base do dia é apagada');

select * from finish();
rollback;
