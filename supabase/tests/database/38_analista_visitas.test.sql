begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

create or replace function privado.hoje() returns date language sql stable set search_path = ''
  as $$ select coalesce(nullif(current_setting('t.hoje', true), '')::date, (now() at time zone 'America/Sao_Paulo')::date) $$;
select set_config('t.hoje', '2026-10-21', true);

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id, latitude, longitude, raio_m)
values ('Aaa', 'Aaa - Escola A', 'CS1', -20.0, -43.8, 150), ('Ddd', 'Ddd - Escola D', 'CS1', -20.1, -43.9, 150);
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000000b1', 'an1@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000f1', 'of@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000f2', 'of2@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, carteira_id, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000000b1', 'Analista Um', 'analista', 'CS1', 'an.um', false);
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000000f1', 'Oficineiro F', 'oficineiro', (select id from public.escolas where sigla = 'Aaa'), 'of.f', false),
  ('00000000-0000-0000-0000-0000000000f2', 'Oficineiro G', 'oficineiro', (select id from public.escolas where sigla = 'Ddd'), 'of.g', false);

create function pg_temp.como(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;
grant execute on function pg_temp.como(text) to authenticated;
create function pg_temp.esc(p_sig text) returns smallint language sql security definer as $$ select id from public.escolas where sigla = p_sig $$;
grant execute on function pg_temp.esc(text) to authenticated;
create function pg_temp.visita(p_extra jsonb) returns jsonb language sql as $$
  select jsonb_build_object('escola', pg_temp.esc('Aaa'), 'data', '2026-10-21', 'tipo', 'Suporte',
                            'observacao', 'Atendimento na escola com a turma do oficineiro') || p_extra
$$;
grant execute on function pg_temp.visita(jsonb) to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
set local role authenticated;
select throws_ok($$select public.registrar_visita(pg_temp.visita('{"objetivo": "Parcialmente"}'))$$, '22023', 'objetivo inválido',
                 'objetivo da visita aceita só Sim ou Não');
select throws_ok($$select public.registrar_visita(pg_temp.visita('{"subtipo": "Intervenção Aulas Regulares"}'))$$, '22023',
                 'escolha a turma e o oficineiro atendidos', 'ação com alunos pede a turma e o oficineiro');
select throws_ok($$select public.registrar_visita(pg_temp.visita(jsonb_build_object('subtipo', 'Intervenção Aulas Regulares', 'turma', '3º ano · Turma A',
                 'oficineiro', '00000000-0000-0000-0000-0000000000f2')))$$, '22023', 'o oficineiro escolhido não atua nesta escola',
                 'oficineiro precisa atuar na escola da visita');
select lives_ok($$select public.registrar_visita(pg_temp.visita(jsonb_build_object('subtipo', 'Intervenção Aulas Regulares', 'turma', '3º ano · Turma A',
                 'oficineiro', '00000000-0000-0000-0000-0000000000f1', 'participantes', 'Prof.ª Ana; Diretora Bia', 'objetivo', 'Sim')))$$,
                'registra a visita com a turma e o oficineiro');
select is((select turma || ' | ' || oficineiro_id::text || ' | ' || participantes from public.visitas), '3º ano · Turma A | 00000000-0000-0000-0000-0000000000f1 | Prof.ª Ana; Diretora Bia',
          'turma, oficineiro e vários participantes gravados');
select lives_ok($$select public.registrar_visita(pg_temp.visita(jsonb_build_object('tipo', 'Acompanhamento', 'subtipo', 'Reunião com a Direção',
                 'turma', '4º ano · Turma B', 'oficineiro', '00000000-0000-0000-0000-0000000000f1', 'objetivo', 'Não')))$$,
                'registra visita sem ação com alunos');
select is((select count(*)::int from public.visitas where subtipo = 'Reunião com a Direção' and turma is null and oficineiro_id is null), 1,
          'sem ação com alunos não guarda turma nem oficineiro');
select lives_ok($$select public.registrar_visita(pg_temp.visita(jsonb_build_object('tipo', 'Formação', 'subtipo', 'Oficina com alunos',
                 'turma', '5º ano · Turma C', 'oficineiro', '00000000-0000-0000-0000-0000000000f1')))$$, 'oficina com alunos também guarda a turma');
select lives_ok($$select public.editar_visita((select id from public.visitas where subtipo = 'Reunião com a Direção'),
                 jsonb_build_object('data', '2026-10-21', 'tipo', 'Acompanhamento', 'subtipo', 'Aulas regulares – Alunos',
                 'turma', '2º ano · Turma A', 'oficineiro', '00000000-0000-0000-0000-0000000000f1', 'observacao', 'Acompanhamento das aulas com os alunos'))$$,
                'corrige a visita para ação com alunos');
select is((select turma from public.visitas where subtipo = 'Aulas regulares – Alunos'), '2º ano · Turma A', 'correção guarda a turma');
reset role;

select is((select count(*)::int from public.visitas where objetivo = 'Parcialmente'), 0, 'nenhuma visita nova com objetivo parcial');

select * from finish();
rollback;
