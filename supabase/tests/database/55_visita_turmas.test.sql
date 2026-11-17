begin;
create extension if not exists pgtap with schema extensions;
select plan(13);

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
select lives_ok($$select public.registrar_visita(pg_temp.visita(jsonb_build_object('subtipo', 'Intervenção Aulas Regulares',
                 'turmas', jsonb_build_array('3º ano · Turma A', ' 3º ano · Turma B ', '3º ano · Turma A', '', '4º ano · Turma C'),
                 'oficineiro', '00000000-0000-0000-0000-0000000000f1')))$$, 'registra a visita com várias turmas');
select is((select turmas from public.visitas), array['3º ano · Turma A', '3º ano · Turma B', '4º ano · Turma C'],
          'turmas gravadas sem repetição nem vazias, na ordem escolhida');
select is((select turma from public.visitas), '3º ano · Turma A', 'turma guarda a primeira da lista');
select lives_ok($$select public.registrar_visita(pg_temp.visita(jsonb_build_object('tipo', 'Formação', 'subtipo', 'Oficina com alunos',
                 'turma', '5º ano · Turma C', 'oficineiro', '00000000-0000-0000-0000-0000000000f1')))$$, 'aceita ainda uma turma só no campo antigo');
select is((select turmas from public.visitas where subtipo = 'Oficina com alunos'), array['5º ano · Turma C'], 'turma única vira lista');
select throws_ok($$select public.registrar_visita(pg_temp.visita(jsonb_build_object('subtipo', 'Intervenção Aulas Regulares',
                 'turmas', jsonb_build_array('', ' '), 'oficineiro', '00000000-0000-0000-0000-0000000000f1')))$$, '22023',
                 'escolha a turma e o oficineiro atendidos', 'lista só com vazios é recusada');
select throws_ok($$select public.registrar_visita(pg_temp.visita(jsonb_build_object('subtipo', 'Intervenção Aulas Regulares',
                 'turmas', '3º ano · Turma A', 'oficineiro', '00000000-0000-0000-0000-0000000000f1')))$$, '22023',
                 'lista de turmas inválida', 'turmas precisa ser lista');
select throws_ok($$select public.registrar_visita(pg_temp.visita(jsonb_build_object('subtipo', 'Intervenção Aulas Regulares',
                 'turmas', (select jsonb_agg('3º ano · Turma ' || n) from generate_series(1, 13) n),
                 'oficineiro', '00000000-0000-0000-0000-0000000000f1')))$$, '22023',
                 'escolha no máximo 12 turmas por visita', 'no máximo 12 turmas');
select throws_ok($$select public.registrar_visita(pg_temp.visita(jsonb_build_object('subtipo', 'Intervenção Aulas Regulares',
                 'turmas', jsonb_build_array(repeat('x', 61)), 'oficineiro', '00000000-0000-0000-0000-0000000000f1')))$$, '22023',
                 'nome de turma muito longo', 'nome de turma até 60 caracteres');
select lives_ok($$select public.editar_visita((select id from public.visitas where subtipo = 'Oficina com alunos'),
                 jsonb_build_object('data', '2026-10-21', 'tipo', 'Formação', 'subtipo', 'Oficina com alunos',
                 'turmas', jsonb_build_array('5º ano · Turma C', '5º ano · Turma D'), 'oficineiro', '00000000-0000-0000-0000-0000000000f1',
                 'observacao', 'Oficina com as duas turmas do quinto ano'))$$, 'corrige a visita para duas turmas');
select is((select turmas from public.visitas where subtipo = 'Oficina com alunos'), array['5º ano · Turma C', '5º ano · Turma D'],
          'correção guarda as duas turmas');
select lives_ok($$select public.editar_visita((select id from public.visitas where subtipo = 'Oficina com alunos'),
                 jsonb_build_object('data', '2026-10-21', 'tipo', 'Acompanhamento', 'subtipo', 'Reunião com a Direção',
                 'turmas', jsonb_build_array('5º ano · Turma C'), 'oficineiro', '00000000-0000-0000-0000-0000000000f1',
                 'observacao', 'Reunião com a direção sobre a oficina'))$$, 'corrige para atividade sem alunos');
reset role;

select is((select count(*)::int from public.visitas where subtipo = 'Reunião com a Direção' and turmas is null and turma is null),
          1, 'sem ação com alunos não guarda turmas');

select * from finish();
rollback;
