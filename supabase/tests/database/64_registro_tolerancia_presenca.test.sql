begin;
create extension if not exists pgtap with schema extensions;
select plan(5);

create or replace function privado.hoje() returns date language sql stable set search_path = ''
  as $$ select coalesce(nullif(current_setting('t.hoje', true), '')::date, (now() at time zone 'America/Sao_Paulo')::date) $$;
select set_config('t.hoje', '2026-11-16', true);

insert into public.carteiras values ('CT1', 'CT1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Cta', 'Cta - Escola Tolerância', 'CT1');
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000f0a01', 'of.tol@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000f0a01', 'Ofic Tolerância', 'oficineiro', (select id from public.escolas where sigla = 'Cta'), 'of.tol', false);
insert into public.presencas (oficineiro_id, escola_id, data, inicio)
values ('00000000-0000-0000-0000-0000000f0a01', (select id from public.escolas where sigla = 'Cta'), '2026-11-16', '2026-11-16 08:05-03');

create function pg_temp.como(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;
grant execute on function pg_temp.como(text) to authenticated;
create temp table ids (k text primary key, v bigint);
grant select, insert on ids to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000f0a01');
set local role authenticated;
select lives_ok($$with x as (insert into public.grade_aulas (dia_semana, horario, inicio, fim, ano, turma, tipo, solucao, componente)
                   values (1, 1, '07:50', '08:40', 5, 'A', 'R', 'Matific', 'Matemática') returning id) insert into ids select 'dentro', id from x$$,
                'atividade que começa 15 minutos antes da presença');
select lives_ok($$with x as (insert into public.grade_aulas (dia_semana, horario, inicio, fim, ano, turma, tipo, solucao, componente)
                   values (1, 2, '07:00', '07:50', 4, 'B', 'R', 'Matific', 'Matemática') returning id) insert into ids select 'fora', id from x$$,
                'atividade que começa uma hora antes da presença');

select lives_ok($$insert into public.aulas_registro (grade_aula_id, data, inicio, fim, turma, tipo, situacao, solucao, componente, presentes, conteudo, objetivo)
                  values ((select v from ids where k = 'dentro'), '2026-11-16', '00:00', '00:50', 'x', 'R', 'Realizada', 'Matific', 'Matemática', 24, 'Frações.', 'Sim')$$,
                'presença iniciada até 15 minutos depois do início aceita o registro');
select throws_ok($$insert into public.aulas_registro (grade_aula_id, data, inicio, fim, turma, tipo, situacao, solucao, componente, presentes, conteudo, objetivo)
                   values ((select v from ids where k = 'fora'), '2026-11-16', '00:00', '00:50', 'x', 'R', 'Realizada', 'Matific', 'Matemática', 20, 'Frações.', 'Sim')$$,
                 '22023', null, 'presença iniciada mais de 15 minutos depois recusa o registro');
select lives_ok($$insert into public.aulas_registro (grade_aula_id, data, inicio, fim, turma, tipo, situacao, motivo)
                  values ((select v from ids where k = 'fora'), '2026-11-16', '00:00', '00:50', 'x', 'R', 'Não realizada', 'Ausência do professor')$$,
                'não realizada continua aceita sem presença');
reset role;

select * from finish();
rollback;
