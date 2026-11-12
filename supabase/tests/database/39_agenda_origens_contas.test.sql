begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

create or replace function privado.hoje() returns date language sql stable set search_path = ''
  as $$ select coalesce(nullif(current_setting('t.hoje', true), '')::date, (now() at time zone 'America/Sao_Paulo')::date) $$;
select set_config('t.hoje', '2026-10-21', true);

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id, latitude, longitude, raio_m) values ('Aaa', 'Aaa - Escola A', 'CS1', -20.0, -43.8, 150);
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000000a1', 'ge@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000c1', 'co@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000b1', 'an@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000d1', 'di@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000f1', 'of@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000000a1', 'Gerente', 'gerente', 'ge.x', false),
  ('00000000-0000-0000-0000-0000000000c1', 'Coordenação', 'coordenador', 'co.x', false);
insert into public.perfis (id, nome, papel, carteira_id, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000000b1', 'Analista', 'analista', 'CS1', 'an.x', false);
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000000d1', 'Direção', 'direcao', (select id from public.escolas where sigla = 'Aaa'), 'di.x', false),
  ('00000000-0000-0000-0000-0000000000f1', 'Oficineiro', 'oficineiro', (select id from public.escolas where sigla = 'Aaa'), 'of.x', false);

create function pg_temp.como(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;
grant execute on function pg_temp.como(text) to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
set local role authenticated;
select lives_ok($$select public.agendar_minha_visita((select id from public.escolas where sigla = 'Aaa'), '2026-10-22', '08:00', 'mapa_calor', 'Acompanhamento · Indicadores de uso')$$,
                'analista agenda visita pelo mapa de calor da Jornada do Usuário');
select throws_ok($$select public.agendar_minha_visita((select id from public.escolas where sigla = 'Aaa'), '2026-10-23', '08:00', 'gerencia')$$, '22023', 'origem da visita inválida',
                 'analista não marca visita como vinculada pela gerência');
select throws_ok($$select public.agendar_minha_visita((select id from public.escolas where sigla = 'Aaa'), '2026-10-23', '08:00', 'relatorio')$$, '22023', 'origem da visita inválida',
                 'relatório de uso foi unido ao mapa de calor');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
set local role authenticated;
select is((select string_agg(papel, ',' order by papel) from public.contas_gestao()), 'coordenador,direcao,oficineiro',
          'coordenador vê só oficineiros, direção e a própria conta');
select is((select count(*)::int from public.contas_gestao() where papel in ('analista', 'gerente')), 0,
          'coordenador não vê analistas nem gerentes');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
select is((select string_agg(papel, ',' order by papel) from public.contas_gestao()), 'analista,coordenador,direcao,gerente,oficineiro',
          'gerente vê todos os perfis');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000d1');
set local role authenticated;
select throws_ok($$select * from public.contas_gestao()$$, '42501', null, 'direção não tem gestão de contas');
reset role;

select * from finish();
rollback;
