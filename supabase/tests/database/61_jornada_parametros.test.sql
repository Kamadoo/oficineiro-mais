begin;
create extension if not exists pgtap with schema extensions;
select plan(25);

insert into public.carteiras values ('JP1', 'JP1 - Teste'), ('JP2', 'JP2 - Teste') on conflict do nothing;
insert into public.escolas (sigla, nome, carteira_id) values
  ('Jpa', 'Jpa - Escola Parametro A', 'JP1'),
  ('Jpb', 'Jpb - Escola Parametro B', 'JP1'),
  ('Jpc', 'Jpc - Escola Parametro C', 'JP2');
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000c2a01', 'jp.admin@exemplo.test'),
  ('00000000-0000-0000-0000-0000000c2a03', 'jp.gerente@exemplo.test'),
  ('00000000-0000-0000-0000-0000000c2a04', 'jp.analista@exemplo.test');
insert into public.perfis (id, nome, papel, escola_id, carteira_id, trocar_senha) values
  ('00000000-0000-0000-0000-0000000c2a01', 'Admin Param', 'administrador', null, null, false),
  ('00000000-0000-0000-0000-0000000c2a03', 'Gerente Param', 'gerente', null, null, false),
  ('00000000-0000-0000-0000-0000000c2a04', 'Analista Param', 'analista', null, 'JP1', false);

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
    jsonb_build_object('h', encode(extensions.digest('jp.aluno6', 'sha256'), 'hex'), 'nome', 'Aluno Seis', 'tipo', 'A',
                       'escola', pg_temp.esc('Jpa'), 'carteira', 'JP1', 'turma', '6º A', 'ano', 6, 'ultimo', '2026-11-20', 'dias', 4),
    jsonb_build_object('h', encode(extensions.digest('jp.aluno3', 'sha256'), 'hex'), 'nome', 'Aluno Tres', 'tipo', 'A',
                       'escola', pg_temp.esc('Jpa'), 'carteira', 'JP1', 'turma', '3º A', 'ano', 3, 'ultimo', '2026-11-20', 'dias', 4),
    jsonb_build_object('h', encode(extensions.digest('jp.prof', 'sha256'), 'hex'), 'nome', 'Professora Lotada', 'tipo', 'P',
                       'escola', pg_temp.esc('Jpa'), 'carteira', 'JP1', 'ultimo', '2026-11-19', 'dias', 9)
  );
$$;
grant execute on function pg_temp.pessoas() to authenticated;
create function pg_temp.escola_de(p_nome text) returns text language sql security definer as $$
  select e.sigla from public.jornada_pessoas j join public.escolas e on e.id = j.escola_id
   where j.nome = p_nome order by j.base_ref desc limit 1;
$$;
grant execute on function pg_temp.escola_de(text) to authenticated;

select ok(not has_table_privilege('authenticated', 'public.jornada_ajustes_lotacao', 'SELECT'),
          'ajustes de lotação não são lidos direto pelo site');
select ok(not has_table_privilege('authenticated', 'public.jornada_parametros', 'UPDATE'), 'parâmetros sem gravação direta');
select ok(not has_function_privilege('authenticated', 'privado.resumo_de_login(text)', 'EXECUTE'),
          'resumo de login só pelo painel');
select ok(not has_function_privilege('anon', 'public.salvar_parametros_jornada(smallint, smallint, text)', 'EXECUTE'),
          'visitante não altera parâmetros');

insert into public.jornada_ajustes_lotacao (escola_base, ano_minimo, escola_destino)
  values (pg_temp.esc('Jpa'), 6, pg_temp.esc('Jpb'));
insert into public.jornada_ajustes_lotacao (login_hash, escola_destino)
  values (extensions.hmac(encode(extensions.digest('jp.prof', 'sha256'), 'hex'), privado.segredo('fsm_jornada_hmac'), 'sha256'),
          pg_temp.esc('Jpc'));

set local role authenticated;
select pg_temp.como('00000000-0000-0000-0000-0000000c2a04');
select throws_ok($$ select public.carregar_base_acessos(date '2026-11-21', null, pg_temp.pessoas()) $$,
                 '42501', null, 'analista não grava a base');
select throws_ok($$ select public.salvar_parametros_jornada(2::smallint, 3::smallint, 'auto') $$,
                 '42501', null, 'analista não altera parâmetros');
select ok(not exists (select 1 from pg_proc where proname = 'definir_carteira_da_unidade'),
          'carteira da unidade só pela tela de escolas do administrador');
select throws_ok($$ select * from public.jornada_ajustes_lotacao() $$, '42501', null, 'analista não vê ajustes de lotação');
select is((select aulas_semana from public.jornada_parametros), 1::smallint, 'analista lê os parâmetros (aulas)');

select pg_temp.como('00000000-0000-0000-0000-0000000c2a03');
select throws_ok($$ select public.carregar_base_acessos(date '2026-11-21', null, pg_temp.pessoas()) $$,
                 '42501', null, 'gerente não grava a base');
select throws_ok($$ select public.salvar_parametros_jornada(2::smallint, 3::smallint, 'auto') $$,
                 '42501', null, 'gerente não altera parâmetros');
select throws_ok($$ select * from public.jornada_ajustes_lotacao() $$, '42501', null, 'gerente não vê ajustes de lotação');

select pg_temp.como('00000000-0000-0000-0000-0000000c2a01');
select is(public.carregar_base_acessos(date '2026-11-21', null, pg_temp.pessoas()) ->> 'pessoas', '3', 'administrador grava a base');
select is(pg_temp.escola_de('Aluno Seis'), 'Jpb', 'aluno do 6º ano vai para a escola do ajuste');
select is(pg_temp.escola_de('Aluno Tres'), 'Jpa', 'aluno do 3º ano fica na escola da base');
select is(pg_temp.escola_de('Professora Lotada'), 'Jpc', 'professora vai para a escola do ajuste pelo login');
select is((select carteira_id from public.jornada_pessoas where nome = 'Professora Lotada'), 'JP2',
          'ajuste leva a carteira da escola de destino');
select is((select count(*)::int from public.jornada_ajustes_lotacao()), 2, 'administrador vê os ajustes');
select is((select sum(afetados)::int from public.jornada_ajustes_lotacao()), 2, 'ajustes com usuários afetados');
select ok((select bool_and(regra not like '%jp.%') from public.jornada_ajustes_lotacao()), 'regra sem o login');

select throws_ok($$ select public.salvar_parametros_jornada(0::smallint, 3::smallint, 'auto') $$,
                 '22023', 'aulas por semana: de 1 a 5', 'meta fora da faixa recusada');
select throws_ok($$ select public.salvar_parametros_jornada(1::smallint, 3::smallint, 'ano') $$,
                 '22023', 'período inválido', 'período inválido recusado');
select lives_ok($$ select public.salvar_parametros_jornada(2::smallint, 4::smallint, 'mes') $$, 'administrador salva parâmetros');
select is((select row(aulas_semana, dias_semana, periodo, autor_nome)::text from public.jornada_parametros),
          '(2,4,mes,"Admin Param")', 'parâmetros gravados com autor');


reset role;
select is((select count(*)::int from auditoria.eventos where acao = 'JORNADA_PARAMETROS'), 1,
          'alteração dos parâmetros na auditoria');

select * from finish();
rollback;
