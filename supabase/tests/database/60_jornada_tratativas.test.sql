begin;
create extension if not exists pgtap with schema extensions;
select plan(30);

insert into public.carteiras values ('JT1', 'JT1 - Teste'), ('JT2', 'JT2 - Teste') on conflict do nothing;
insert into public.escolas (sigla, nome, carteira_id) values
  ('Jta', 'Jta - Escola Tratativa A', 'JT1'),
  ('Jtb', 'Jtb - Escola Tratativa B', 'JT2');
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000c1a01', 'jt.admin@exemplo.test'),
  ('00000000-0000-0000-0000-0000000c1a02', 'jt.coord@exemplo.test'),
  ('00000000-0000-0000-0000-0000000c1a03', 'jt.gerente@exemplo.test'),
  ('00000000-0000-0000-0000-0000000c1a04', 'jt.analista1@exemplo.test'),
  ('00000000-0000-0000-0000-0000000c1a05', 'jt.analista2@exemplo.test');
insert into public.perfis (id, nome, papel, escola_id, carteira_id, trocar_senha) values
  ('00000000-0000-0000-0000-0000000c1a01', 'Admin Trat', 'administrador', null, null, false),
  ('00000000-0000-0000-0000-0000000c1a02', 'Coord Trat', 'coordenador', null, null, false),
  ('00000000-0000-0000-0000-0000000c1a03', 'Gerente Trat', 'gerente', null, null, false),
  ('00000000-0000-0000-0000-0000000c1a04', 'Analista Um', 'analista', null, 'JT1', false),
  ('00000000-0000-0000-0000-0000000c1a05', 'Analista Dois', 'analista', null, 'JT2', false);

create function pg_temp.como(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;
grant execute on function pg_temp.como(text) to authenticated;
create function pg_temp.esc(p_sigla text) returns smallint language sql as $$
  select id from public.escolas where sigla = p_sigla;
$$;
grant execute on function pg_temp.esc(text) to authenticated;
create function pg_temp.pessoas() returns jsonb language sql as $$
  select jsonb_build_array(
    jsonb_build_object('h', encode(extensions.digest('jt.aluno', 'sha256'), 'hex'), 'nome', 'Aluno Trat', 'tipo', 'A',
                       'escola', pg_temp.esc('Jta'), 'carteira', 'JT1', 'turma', '9º A', 'ano', 9, 'ultimo', '2026-11-20',
                       'dias', 4, 'matricula', '123456', 'email', 'aluno.123456@exemplo.test'),
    jsonb_build_object('h', encode(extensions.digest('jt.prof', 'sha256'), 'hex'), 'nome', 'Professor Trat', 'tipo', 'P',
                       'escola', pg_temp.esc('Jta'), 'carteira', 'JT1', 'ultimo', '2026-09-01', 'dias', 9, 'funcao', 'Regente'),
    jsonb_build_object('h', encode(extensions.digest('jt.serv', 'sha256'), 'hex'), 'nome', 'Servidor Trat', 'tipo', 'S',
                       'escola', pg_temp.esc('Jta'), 'carteira', 'JT1')
  );
$$;
grant execute on function pg_temp.pessoas() to authenticated;
create function pg_temp.pessoa(p_nome text) returns bigint language sql as $$
  select id from public.jornada_pessoas where nome = p_nome order by base_ref desc limit 1;
$$;
grant execute on function pg_temp.pessoa(text) to authenticated;

select ok(not has_column_privilege('authenticated', 'public.jornada_tratativas', 'login_hash', 'SELECT'),
          'resumo do login das tratativas não é lido pelo site');
select ok(not has_table_privilege('authenticated', 'public.jornada_tratativas', 'INSERT'), 'tratativas sem gravação direta');
select ok(not has_function_privilege('anon', 'public.tratar_usuario(bigint, text, smallint, text)', 'EXECUTE'),
          'visitante não trata usuários');

set local role authenticated;
select pg_temp.como('00000000-0000-0000-0000-0000000c1a01');
select throws_ok($$ select public.carregar_base_acessos(date '2026-11-21', null,
                    jsonb_build_array(jsonb_build_object('h', encode(extensions.digest('x', 'sha256'), 'hex'), 'nome', 'Fulano',
                                                         'tipo', 'A', 'escola', pg_temp.esc('Jta'), 'email', 'sem-arroba'))) $$,
                 '22023', 'pessoa 1: e-mail inválido', 'e-mail inválido recusado na carga');
select is(public.carregar_base_acessos(date '2026-11-20', null, pg_temp.pessoas()) ->> 'pessoas', '3', 'base anterior carregada');
select is(public.carregar_base_acessos(date '2026-11-21', null, pg_temp.pessoas()) ->> 'pessoas', '3', 'base do dia carregada');
reset role;
select is((select matricula || ' ' || email from public.jornada_pessoas where nome = 'Aluno Trat' and base_ref = '2026-11-21'),
          '123456 aluno.123456@exemplo.test', 'matrícula e e-mail gravados na carga');
select is((select funcao from public.jornada_pessoas where nome = 'Professor Trat' and base_ref = '2026-11-21'), 'Regente',
          'função gravada na carga');

set local role authenticated;
select pg_temp.como('00000000-0000-0000-0000-0000000c1a05');
select throws_ok($$ select public.tratar_usuario(pg_temp.pessoa('Professor Trat'), 'licenca') $$, '22023', null,
                 'analista de outra carteira não alcança o usuário');
select pg_temp.como('00000000-0000-0000-0000-0000000c1a02');
select throws_ok($$ select public.tratar_usuario(pg_temp.pessoa('Professor Trat'), 'licenca') $$, '42501', null,
                 'coordenador não trata usuários');
select pg_temp.como('00000000-0000-0000-0000-0000000c1a04');
select throws_ok($$ select public.tratar_usuario((select id from public.jornada_pessoas where nome = 'Servidor Trat'
                                                   and base_ref = '2026-11-20'), 'licenca') $$,
                 '22023', 'use a base de acessos mais recente', 'só a base mais recente é tratada');
select throws_ok($$ select public.tratar_usuario(pg_temp.pessoa('Professor Trat'), 'saiu', null, ' ') $$,
                 '22023', 'informe o motivo da saída', 'saída exige motivo');
select throws_ok($$ select public.tratar_usuario(pg_temp.pessoa('Aluno Trat'), 'transferido', pg_temp.esc('Jta')) $$,
                 '22023', 'a nova escola é a escola atual', 'transferência para a mesma escola recusada');
select ok(public.tratar_usuario(pg_temp.pessoa('Professor Trat'), 'saiu', null, 'pediu exoneração') > 0,
          'analista marca saída da rede');
select is((select situacao from public.jornada_pessoas where nome = 'Professor Trat' and base_ref = '2026-11-21'), 'pend_desat',
          'saída fica pendente e o usuário continua nos indicadores');
select throws_ok($$ select public.tratar_usuario(pg_temp.pessoa('Professor Trat'), 'licenca') $$,
                 '22023', 'este usuário já está com o gerente', 'usuário pendente não é marcado de novo');
select ok(public.tratar_usuario(pg_temp.pessoa('Aluno Trat'), 'transferido', pg_temp.esc('Jtb'), 'mudou de bairro') > 0,
          'analista transfere o aluno');
select is((select count(*)::int from public.jornada_pessoas where nome = 'Aluno Trat' and base_ref = '2026-11-21'), 0,
          'transferido sai na hora da carteira de origem');
select ok(public.tratar_usuario(pg_temp.pessoa('Servidor Trat'), 'licenca', null, 'licença sem data') > 0,
          'analista marca licença sem vencimento');
select throws_ok($$ select public.decidir_tratativas(array[(select max(id) from public.jornada_tratativas)], 'manter') $$,
                 '42501', null, 'analista não decide tratativas');

select pg_temp.como('00000000-0000-0000-0000-0000000c1a05');
select is((select escola_origem_id || ' ' || coalesce(turma, 'sem turma') || ' ' || carteira_id from public.jornada_pessoas
            where nome = 'Aluno Trat' and base_ref = '2026-11-21'),
          pg_temp.esc('Jta') || ' sem turma JT2', 'analista de destino vê o aluno com a origem e a turma a definir');
select is((select count(*)::int from public.jornada_tratativas where ciente_em is null and acao = 'transferido'), 1,
          'analista de destino vê o aviso da transferência');
select is(public.ciente_tratativas(), 1, 'analista de destino dá ciente');

select pg_temp.como('00000000-0000-0000-0000-0000000c1a03');
select throws_ok($$ select public.decidir_tratativas(array[(select id from public.jornada_tratativas where acao = 'licenca')], 'desativar') $$,
                 '22023', 'há usuários que não estão nesta situação', 'decisão fora da situação recusada');
select is(public.decidir_tratativas(array[(select id from public.jornada_tratativas where acao = 'licenca')], 'manter'), 1,
          'gerente mantém ativo o usuário de licença');
select is(public.decidir_tratativas(array[(select id from public.jornada_tratativas where acao = 'saiu')], 'desativar'), 1,
          'gerente marca o usuário como desativado');
select is((select count(*)::int from public.jornada_pessoas where nome = 'Professor Trat'), 0,
          'desativado fica fora de todas as bases');

select pg_temp.como('00000000-0000-0000-0000-0000000c1a01');
select is(public.carregar_base_acessos(date '2026-11-21', null, pg_temp.pessoas(), true) ->> 'pessoas', '3',
          'nova carga do B.I. traz o usuário na escola antiga');
reset role;
select is((select string_agg(nome || ':' || (select sigla from public.escolas e where e.id = j.escola_id) || ':' || coalesce(situacao, '-'),
                             ', ' order by nome)
             from public.jornada_pessoas j where base_ref = '2026-11-21'),
          'Aluno Trat:Jtb:transferido, Professor Trat:Jta:desativado, Servidor Trat:Jta:mantido',
          'transferência, desativação e decisão do gerente continuam valendo depois da nova carga');
select is((select count(*)::int from auditoria.eventos where acao = 'JORNADA_TRATATIVA'), 3, 'tratativas registradas na auditoria');

select * from finish();
rollback;
