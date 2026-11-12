begin;
create extension if not exists pgtap with schema extensions;
select plan(13);

create or replace function privado.hoje() returns date language sql stable set search_path = ''
  as $$ select coalesce(nullif(current_setting('t.hoje', true), '')::date, (now() at time zone 'America/Sao_Paulo')::date) $$;
select set_config('t.hoje', '2026-10-21', true);

insert into public.carteiras values ('CS1', 'CS1 - Teste'), ('CS2', 'CS2 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Aaa', 'Aaa - Escola A', 'CS1'), ('Bbb', 'Bbb - Escola B', 'CS2');
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000000a1', 'ge@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000b1', 'an1@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000b2', 'an2@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000f1', 'of@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000000a1', 'Gerente', 'gerente', 'ge.x', false);
insert into public.perfis (id, nome, papel, carteira_id, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000000b1', 'Analista Um', 'analista', 'CS1', 'an.um', false),
  ('00000000-0000-0000-0000-0000000000b2', 'Analista Dois', 'analista', 'CS2', 'an.dois', false);
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000000f1', 'Oficineiro F', 'oficineiro', (select id from public.escolas where sigla = 'Aaa'), 'of.f', false);

create function pg_temp.como(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;
grant execute on function pg_temp.como(text) to authenticated;
create function pg_temp.esc(p_sig text) returns smallint language sql security definer as $$ select id from public.escolas where sigla = p_sig $$;
grant execute on function pg_temp.esc(text) to authenticated;

select is((select relrowsecurity from pg_class where oid = 'public.visitas_agenda'::regclass), true, 'agenda de visitas tem RLS');

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
select lives_ok($$select public.agendar_visita('00000000-0000-0000-0000-0000000000b1', pg_temp.esc('Aaa'), '2026-10-22', '08:00', 'mapa_calor', 'Acompanhamento', 'Professores', 'Engajamento abaixo de 20%')$$, 'gerente agenda visita');
select throws_ok($$select public.agendar_visita('00000000-0000-0000-0000-0000000000b1', pg_temp.esc('Aaa'), '2026-10-22', '09:00', 'mapa_calor')$$, '22023', null, 'não repete a mesma escola no mesmo dia');
select throws_ok($$select public.agendar_visita('00000000-0000-0000-0000-0000000000b1', pg_temp.esc('Bbb'), '2026-10-23', '08:00', 'demanda')$$, '22023', null, 'escola precisa ser da carteira do analista');
select throws_ok($$select public.agendar_visita('00000000-0000-0000-0000-0000000000b1', pg_temp.esc('Aaa'), '2026-10-24', '08:00', 'demanda')$$, '22023', null, 'não agenda em fim de semana');
select throws_ok($$select public.agendar_visita('00000000-0000-0000-0000-0000000000b1', pg_temp.esc('Aaa'), '2026-10-20', '08:00', 'demanda')$$, '22023', null, 'não agenda no passado');
select throws_ok($$select public.agendar_visita('00000000-0000-0000-0000-0000000000f1', pg_temp.esc('Aaa'), '2026-10-23', '08:00', 'demanda')$$, '22023', null, 'só agenda para analista');
select lives_ok($$select public.agendar_visita('00000000-0000-0000-0000-0000000000b2', pg_temp.esc('Bbb'), '2026-10-23', null, 'relatorio')$$, 'agenda para outro analista');
select throws_ok($$insert into public.visitas_agenda (analista_id, escola_id, data, origem) values ('00000000-0000-0000-0000-0000000000b1', pg_temp.esc('Aaa'), '2026-10-26', 'demanda')$$, '42501', null, 'não grava direto na tabela');
select lives_ok($$select public.cancelar_visita_agenda((select id from public.visitas_agenda where analista_id = '00000000-0000-0000-0000-0000000000b2'))$$, 'gerente cancela visita');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
set local role authenticated;
select is((select count(*)::int from public.visitas_agenda), 1, 'analista vê só a própria agenda');
select throws_ok($$select public.agendar_visita('00000000-0000-0000-0000-0000000000b1', pg_temp.esc('Aaa'), '2026-10-27', '08:00', 'demanda')$$, '42501', null, 'analista não agenda pela gerência');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000f1');
set local role authenticated;
select is((select count(*)::int from public.visitas_agenda), 0, 'oficineiro não vê a agenda dos analistas');
reset role;

select * from finish();
rollback;
