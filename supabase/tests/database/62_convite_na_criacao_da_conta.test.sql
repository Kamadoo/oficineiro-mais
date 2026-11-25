begin;
create extension if not exists pgtap with schema extensions;
select plan(15);

insert into public.carteiras values ('CN1', 'CN1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Cna', 'Cna - Escola Nova Conta', 'CN1');
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000d0a01', 'adm.nova@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000d0b01', 'ger.nova@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000d0c01', 'co.nova@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000d0e01', 'an.nova@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000d0f01', 'of1.nova@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000d0f02', 'of2.nova@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000d0f03', 'of3.nova@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000d0f04', 'of4.nova@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000d0a01', 'Admin Nova', 'administrador', 'adm.nova', false),
  ('00000000-0000-0000-0000-0000000d0b01', 'Gerente Nova', 'gerente', 'ger.nova', false),
  ('00000000-0000-0000-0000-0000000d0c01', 'Coord Nova', 'coordenador', 'co.nova', false);
insert into public.perfis (id, nome, papel, carteira_id, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000d0e01', 'Analista Nova', 'analista', 'CN1', 'an.nova', false);
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000d0f01', 'Ofic Do Gerente', 'oficineiro', (select id from public.escolas where sigla = 'Cna'), null, true),
  ('00000000-0000-0000-0000-0000000d0f02', 'Ofic Do Coord', 'oficineiro', (select id from public.escolas where sigla = 'Cna'), null, true),
  ('00000000-0000-0000-0000-0000000d0f03', 'Ofic Antigo', 'oficineiro', (select id from public.escolas where sigla = 'Cna'), null, true),
  ('00000000-0000-0000-0000-0000000d0f04', 'Ofic Do Admin', 'oficineiro', (select id from public.escolas where sigla = 'Cna'), null, true);
insert into auditoria.eventos (usuario_id, papel, aal, acao, tabela, registro, em) values
  ('00000000-0000-0000-0000-0000000d0b01', 'gerente', 'aal2', 'CADASTRAR_USUARIO', 'perfis', '00000000-0000-0000-0000-0000000d0f01', now()),
  ('00000000-0000-0000-0000-0000000d0c01', 'coordenador', 'aal2', 'CADASTRAR_USUARIO', 'perfis', '00000000-0000-0000-0000-0000000d0f02', now()),
  ('00000000-0000-0000-0000-0000000d0b01', 'gerente', 'aal2', 'CADASTRAR_USUARIO', 'perfis', '00000000-0000-0000-0000-0000000d0f03', now() - interval '2 hours'),
  ('00000000-0000-0000-0000-0000000d0a01', 'administrador', 'aal2', 'CADASTRAR_USUARIO', 'perfis', '00000000-0000-0000-0000-0000000d0f04', now());

set local role service_role;
select throws_ok($$ select * from public.convites_reservar('00000000-0000-0000-0000-0000000d0e01', array['00000000-0000-0000-0000-0000000d0f01']::uuid[], false) $$,
                 '42501', null, 'analista não reserva convites');
select throws_ok($$ select * from public.convites_reservar('00000000-0000-0000-0000-0000000d0b01', array['00000000-0000-0000-0000-0000000d0f01']::uuid[], true) $$,
                 '42501', null, 'gerente não reenvia');
select throws_ok($$ select * from public.convites_reservar('00000000-0000-0000-0000-0000000d0b01',
                   array['00000000-0000-0000-0000-0000000d0f01', '00000000-0000-0000-0000-0000000d0f02']::uuid[], false) $$,
                 '42501', null, 'gerente não envia em grupo');
select is((select resultado from public.convites_reservar('00000000-0000-0000-0000-0000000d0b01', array['00000000-0000-0000-0000-0000000d0f02']::uuid[], false)),
          'indisponivel', 'gerente não envia para conta criada por outra pessoa');
select is((select resultado from public.convites_reservar('00000000-0000-0000-0000-0000000d0b01', array['00000000-0000-0000-0000-0000000d0f03']::uuid[], false)),
          'indisponivel', 'gerente não envia para conta criada há mais de uma hora');
select is((select resultado from public.convites_reservar('00000000-0000-0000-0000-0000000d0c01', array['00000000-0000-0000-0000-0000000d0f04']::uuid[], false)),
          'indisponivel', 'coordenador não envia para conta criada pelo administrador');

create temp table g1 as
  select * from public.convites_reservar('00000000-0000-0000-0000-0000000d0b01', array['00000000-0000-0000-0000-0000000d0f01']::uuid[], false);
select is((select resultado || ' ' || email from g1), 'reservado of1.nova@exemplo.test', 'gerente reserva o convite da conta que acabou de criar');
select is(public.convites_concluir('00000000-0000-0000-0000-0000000d0b01',
          jsonb_build_array(jsonb_build_object('convite_id', (select convite_id from g1), 'ok', false, 'detalhe', 'recusado'))),
          '{"falhas": 1, "enviados": 0}'::jsonb, 'gerente registra a falha do envio');
select is((select resultado from public.convites_reservar('00000000-0000-0000-0000-0000000d0b01', array['00000000-0000-0000-0000-0000000d0f01']::uuid[], false)),
          'ja_enviado', 'depois de uma tentativa, o gerente não tenta de novo');
select is((select resultado from public.convites_reservar('00000000-0000-0000-0000-0000000d0a01', array['00000000-0000-0000-0000-0000000d0f01']::uuid[], false)),
          'reservado', 'o administrador reenvia pela aba Convites depois da falha');

create temp table c1 as
  select * from public.convites_reservar('00000000-0000-0000-0000-0000000d0c01', array['00000000-0000-0000-0000-0000000d0f02']::uuid[], false);
select is((select resultado from c1), 'reservado', 'coordenador reserva o convite da conta que acabou de criar');
select throws_ok($$ select public.convites_concluir('00000000-0000-0000-0000-0000000d0e01', '[]'::jsonb) $$,
                 '42501', null, 'analista não conclui convites');
select is(public.convites_concluir('00000000-0000-0000-0000-0000000d0c01',
          jsonb_build_array(jsonb_build_object('convite_id', (select convite_id from c1), 'ok', true))),
          '{"falhas": 0, "enviados": 1}'::jsonb, 'coordenador conclui o envio');
reset role;

select is((select papel from auditoria.eventos where acao = 'CONVITE_PRIMEIRO_ACESSO' and registro = '00000000-0000-0000-0000-0000000d0f02'),
          'coordenador', 'a auditoria guarda o papel de quem enviou');
select is((select count(*)::int from privado.convites where usuario_id = '00000000-0000-0000-0000-0000000d0f04'),
          0, 'nenhum convite reservado para conta de outra pessoa');

select * from finish();
rollback;
