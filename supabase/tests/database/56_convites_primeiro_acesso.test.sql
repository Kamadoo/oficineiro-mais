begin;
create extension if not exists pgtap with schema extensions;
select plan(26);

insert into public.carteiras values ('CV1', 'CV1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Cva', 'Cva - Escola Convite', 'CV1');
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000c0a01', 'adm.convite@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000c0a02', 'adm2.convite@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000c0c01', 'co.convite@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000c0f01', 'of1.convite@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000c0f02', 'of2.convite@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000c0f03', 'of3.convite@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000c0f04', 'of4.convite@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000c0e01', 'an.convite@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000c0a01', 'Admin Convite', 'administrador', 'adm.convite', false),
  ('00000000-0000-0000-0000-0000000c0a02', 'Admin Novo', 'administrador', null, true),
  ('00000000-0000-0000-0000-0000000c0c01', 'Coord Convite', 'coordenador', 'co.convite', false);
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha, ativo) values
  ('00000000-0000-0000-0000-0000000c0f01', 'Ofic Pendente', 'oficineiro', (select id from public.escolas where sigla = 'Cva'), null, true, true),
  ('00000000-0000-0000-0000-0000000c0f02', 'Ofic Ativo', 'oficineiro', (select id from public.escolas where sigla = 'Cva'), 'of.ativo', false, true),
  ('00000000-0000-0000-0000-0000000c0f03', 'Ofic Desativado', 'oficineiro', (select id from public.escolas where sigla = 'Cva'), null, true, false),
  ('00000000-0000-0000-0000-0000000c0f04', 'Ofic Antigo', 'oficineiro', (select id from public.escolas where sigla = 'Cva'), null, true, true);
insert into public.perfis (id, nome, papel, carteira_id, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000c0e01', 'Analista Pendente', 'analista', 'CV1', null, true);

create function pg_temp.como(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;
grant execute on function pg_temp.como(text) to authenticated;

set local role authenticated;
select pg_temp.como('00000000-0000-0000-0000-0000000c0a01');
select is((select count(*)::int from public.convites_pendentes() where nome like '%Convite' or nome like 'Ofic%' or nome like 'Analista%'),
          3, 'o administrador vê só as contas ativas que aguardam o primeiro acesso');
select is((select string_agg(nome, ',' order by nome) from public.convites_pendentes() where nome in ('Analista Pendente', 'Ofic Pendente')),
          'Analista Pendente,Ofic Pendente', 'lista oficineiro e analista pendentes');
select is((select count(*)::int from public.convites_pendentes() where papel = 'administrador'), 0, 'contas de administrador não entram');
select is((select situacao || ' ' || envios from public.convites_pendentes() where nome = 'Ofic Pendente'), 'nunca 0', 'sem convite: nunca enviado');
select is((select carteira_id || ' ' || escola from public.convites_pendentes() where nome = 'Ofic Pendente'), 'CV1 Cva - Escola Convite',
          'oficineiro herda a carteira da escola');
select is((select email from public.convites_pendentes() where nome = 'Analista Pendente'), 'an.convite@exemplo.test', 'traz o e-mail');
select pg_temp.como('00000000-0000-0000-0000-0000000c0c01');
select throws_ok($$ select * from public.convites_pendentes() $$, '42501', null, 'o coordenador não lista convites');
select throws_ok($$ select * from public.convites_reservar('00000000-0000-0000-0000-0000000c0a01', array['00000000-0000-0000-0000-0000000c0f01']::uuid[], false) $$,
                 '42501', null, 'usuário logado não reserva convites');
select throws_ok($$ select public.convites_concluir('00000000-0000-0000-0000-0000000c0a01', '[]'::jsonb) $$,
                 '42501', null, 'usuário logado não conclui convites');
select throws_ok($$ select count(*) from privado.convites $$, '42501', null, 'usuário logado não lê a tabela de convites');
reset role;

set local role anon;
select throws_ok($$ select * from public.convites_pendentes() $$, '42501', null, 'visitante não lista convites');
reset role;

set local role service_role;
select throws_ok($$ select * from public.convites_reservar('00000000-0000-0000-0000-0000000c0c01', array['00000000-0000-0000-0000-0000000c0f01']::uuid[], false) $$,
                 '42501', null, 'só administrador reserva');
select throws_ok($$ select * from public.convites_reservar('00000000-0000-0000-0000-0000000c0a02', array['00000000-0000-0000-0000-0000000c0f01']::uuid[], false) $$,
                 '42501', null, 'administrador sem primeiro acesso não reserva');
select throws_ok($$ select * from public.convites_reservar('00000000-0000-0000-0000-0000000c0a01', (select array_agg(gen_random_uuid()) from generate_series(1, 51)), false) $$,
                 '22023', null, 'no máximo 50 por vez');

create temp table r1 as
  select * from public.convites_reservar('00000000-0000-0000-0000-0000000c0a01',
    array['00000000-0000-0000-0000-0000000c0f01', '00000000-0000-0000-0000-0000000c0f02', '00000000-0000-0000-0000-0000000c0f03',
          '00000000-0000-0000-0000-0000000c0f01']::uuid[], false);
select is((select string_agg(resultado, ',' order by usuario_id) from r1), 'reservado,indisponivel,indisponivel',
          'reserva só a conta pendente, sem repetir');
select is((select email from r1 where resultado = 'reservado'), 'of1.convite@exemplo.test', 'a reserva devolve o e-mail');
select is((select resultado from public.convites_reservar('00000000-0000-0000-0000-0000000c0a01',
          array['00000000-0000-0000-0000-0000000c0f01']::uuid[], true)), 'em_envio', 'não reserva duas vezes ao mesmo tempo');
select is(public.convites_concluir('00000000-0000-0000-0000-0000000c0a02',
          jsonb_build_array(jsonb_build_object('convite_id', (select convite_id from r1 where resultado = 'reservado'), 'ok', true))),
          '{"falhas": 0, "enviados": 0}'::jsonb, 'outro administrador não conclui a reserva alheia');
select is(public.convites_concluir('00000000-0000-0000-0000-0000000c0a01',
          jsonb_build_array(jsonb_build_object('convite_id', (select convite_id from r1 where resultado = 'reservado'), 'ok', true))),
          '{"falhas": 0, "enviados": 1}'::jsonb, 'conclui o envio');
select is((select resultado from public.convites_reservar('00000000-0000-0000-0000-0000000c0a01',
          array['00000000-0000-0000-0000-0000000c0f01']::uuid[], false)), 'ja_enviado', 'sem confirmação não reenvia');
create temp table r2 as
  select * from public.convites_reservar('00000000-0000-0000-0000-0000000c0a01', array['00000000-0000-0000-0000-0000000c0f01']::uuid[], true);
select is((select resultado from r2), 'reservado', 'com confirmação reenvia');
select is(public.convites_concluir('00000000-0000-0000-0000-0000000c0a01',
          jsonb_build_array(jsonb_build_object('convite_id', (select convite_id from r2), 'ok', false, 'detalhe', 'recusado'))),
          '{"falhas": 1, "enviados": 0}'::jsonb, 'registra a falha');
reset role;
insert into privado.convites (usuario_id, enviado_por, criado_em)
  values ('00000000-0000-0000-0000-0000000c0f04', '00000000-0000-0000-0000-0000000c0a01', now() - interval '1 hour');
set local role service_role;
select is((select resultado from public.convites_reservar('00000000-0000-0000-0000-0000000c0a01',
          array['00000000-0000-0000-0000-0000000c0f04']::uuid[], false)), 'reservado', 'reserva antiga interrompida não bloqueia');
reset role;

select is((select count(*)::int from auditoria.eventos where acao in ('CONVITE_PRIMEIRO_ACESSO', 'CONVITE_FALHOU')
            and registro = '00000000-0000-0000-0000-0000000c0f01'), 2, 'envio e falha ficam na auditoria');

set local role authenticated;
select pg_temp.como('00000000-0000-0000-0000-0000000c0a01');
select is((select situacao || ' ' || envios || ' ' || ultimo_por from public.convites_pendentes() where nome = 'Ofic Pendente'),
          'falhou 1 Admin Convite', 'a lista mostra a última tentativa, o total enviado e quem enviou');
select ok((select ultimo_envio is not null from public.convites_pendentes() where nome = 'Ofic Pendente'), 'guarda quando foi enviado');
reset role;

select * from finish();
rollback;
