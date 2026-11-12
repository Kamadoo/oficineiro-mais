begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

create or replace function privado.hoje() returns date language sql stable set search_path = ''
  as $$ select coalesce(nullif(current_setting('t.hoje', true), '')::date, (now() at time zone 'America/Sao_Paulo')::date) $$;
select set_config('t.hoje', '2026-10-22', true);

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Aaa', 'Aaa - Escola A', 'CS1'), ('Bbb', 'Bbb - Escola B', 'CS1');
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000000e1', 'dir@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000e2', 'dir2@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000f1', 'of@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000f2', 'of2@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000000e1', 'Direção A', 'direcao', (select id from public.escolas where sigla = 'Aaa'), 'dir.a', false),
  ('00000000-0000-0000-0000-0000000000e2', 'Direção B', 'direcao', (select id from public.escolas where sigla = 'Bbb'), 'dir.b', false),
  ('00000000-0000-0000-0000-0000000000f1', 'Oficineiro F', 'oficineiro', (select id from public.escolas where sigla = 'Aaa'), 'of.f', false),
  ('00000000-0000-0000-0000-0000000000f2', 'Oficineiro G', 'oficineiro', (select id from public.escolas where sigla = 'Aaa'), 'of.g', false);

create temp table ids (k text primary key, v bigint);
grant select on ids to authenticated;
create function pg_temp.aula(p_of text, p_ini text) returns bigint language sql as $$
  insert into public.aulas_registro (oficineiro_id, escola_id, data, inicio, fim, turma, tipo, situacao, presentes, matriculados, conteudo)
  select p.id, p.escola_id, '2026-10-20', p_ini::time, p_ini::time + interval '50 minutes', '3A', 'R', 'Realizada', 20, 25, 'Aula de frações.'
    from public.perfis p where p.id = p_of::uuid
  returning id;
$$;
insert into ids values
  ('a1', pg_temp.aula('00000000-0000-0000-0000-0000000000f1', '07:00')),
  ('a2', pg_temp.aula('00000000-0000-0000-0000-0000000000f1', '08:00')),
  ('a3', pg_temp.aula('00000000-0000-0000-0000-0000000000f1', '09:00')),
  ('g1', pg_temp.aula('00000000-0000-0000-0000-0000000000f2', '07:00'));

create function pg_temp.como(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;
grant execute on function pg_temp.como(text) to authenticated;
create function pg_temp.hist(p_k text) returns text language sql security definer as $$
  select coalesce(string_agg(evento || ':' || coalesce(texto, '-'), ' | ' order by em, id), '')
    from public.check_historico where aula_id = (select v from ids where k = p_k);
$$;
grant execute on function pg_temp.hist(text) to authenticated;

select is((select relrowsecurity from pg_class where oid = 'public.check_historico'::regclass), true, 'histórico do check tem RLS');

select pg_temp.como('00000000-0000-0000-0000-0000000000e1');
set local role authenticated;
select lives_ok($$select public.conferir_aula((select v from ids where k = 'a1'), false, 'Número de presentes divergente · eram 15')$$, 'direção contesta');
select lives_ok($$select public.conferir_aula((select v from ids where k = 'a2'), true)$$, 'direção confirma');
select is(public.conferir_aulas(array[(select v from ids where k = 'a3'), (select v from ids where k = 'g1')]), 2, 'confirma várias');
select is(pg_temp.hist('a1'), 'contestada:Número de presentes divergente · eram 15', 'contestação entra no histórico');
select is(pg_temp.hist('a2') || ' / ' || pg_temp.hist('a3'), 'confirmada:- / confirmada:-', 'confirmações entram no histórico');
select throws_ok($$insert into public.check_historico (aula_id, oficineiro_id, escola_id, evento) values ((select v from ids where k = 'a1'), '00000000-0000-0000-0000-0000000000f1', (select id from public.escolas where sigla = 'Aaa'), 'confirmada')$$, '42501', null, 'direção não grava o histórico direto');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000f1');
set local role authenticated;
select lives_ok($$update public.aulas_registro set presentes = 15, conteudo = 'Aula de frações com jogo.' where id = (select v from ids where k = 'a1')$$, 'oficineiro corrige');
select is(pg_temp.hist('a1'), 'contestada:Número de presentes divergente · eram 15 | corrigida:Presentes: 20/25 → 15/25 · Descrição da atividade ajustada', 'correção descreve o que mudou');
select is((select count(*)::int from public.check_historico), 4, 'oficineiro vê só o histórico das próprias atividades');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000e1');
set local role authenticated;
select lives_ok($$select public.conferir_aula((select v from ids where k = 'a1'), true)$$, 'direção confirma depois da correção');
select is(pg_temp.hist('a1'), 'contestada:Número de presentes divergente · eram 15 | corrigida:Presentes: 20/25 → 15/25 · Descrição da atividade ajustada | confirmada:-', 'histórico completo da contestação');
select is((select count(*)::int from public.check_historico), 6, 'direção lê o histórico da escola');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000e2');
set local role authenticated;
select is((select count(*)::int from public.check_historico), 0, 'direção de outra escola não vê o histórico');
reset role;

select * from finish();
rollback;
