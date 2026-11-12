begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Aaa', 'Aaa - Escola A', 'CS1');
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000000a1', 'of.a@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000b1', 'of.b@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha)
select x.id::uuid, x.nome, 'oficineiro', e.id, x.usuario, false
  from (values ('00000000-0000-0000-0000-0000000000a1', 'Oficineiro A', 'of.a'),
               ('00000000-0000-0000-0000-0000000000b1', 'Oficineiro B', 'of.b')) x(id, nome, usuario)
  cross join public.escolas e;

create temp table dia as
select max(x)::date as d from generate_series(privado.ciclo_inicio(privado.ciclo_de(privado.hoje())), privado.hoje(), interval '1 day') x
 where extract(isodow from x) <= 5;
grant select on dia to authenticated;
insert into public.presencas (oficineiro_id, escola_id, data, inicio, fim)
select '00000000-0000-0000-0000-0000000000a1', (select id from public.escolas), d, (d + time '07:00') at time zone 'America/Sao_Paulo',
       (d + time '12:00') at time zone 'America/Sao_Paulo'
  from dia;

create function pg_temp.como(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;
grant execute on function pg_temp.como(text) to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
insert into public.grade_aulas (dia_semana, inicio, fim, ano, turma, tipo, solucao, professor, componente)
select extract(isodow from d), '07:50', '09:30', 3, 'B', 'R', 'Matific', 'Prof. Grade', 'Matemática' from dia;
insert into public.grade_aulas (dia_semana, inicio, fim, ano, turma, tipo, oficina)
select case when extract(isodow from d) = 5 then 1 else extract(isodow from d) + 1 end, '07:00', '07:50', 4, 'A', 'P', 'Programa Construtores – Minecraft' from dia;

select lives_ok($$insert into public.aulas_registro (grade_aula_id, data, inicio, fim, turma, tipo, solucao, situacao, presentes, matriculados,
                    conteudo, atividade, componente, objetivo, engajamento, proxima_aula, professor_aula, mudanca)
                  select g.id, d.d, g.inicio, g.fim, '3º ano · Turma B', g.tipo, 'Minecraft Education', 'Realizada', 22, 25,
                         'Construção de cercas e cálculo de área.', 'Área e perímetro', 'Matemática', 'Sim', 4, 'Continuar perímetro', 'Prof. Substituta', 'A professora regente faltou.'
                    from public.grade_aulas g, dia d where g.ano = 3$$,
                'registra a aula da grade com os dados novos (mudança de última hora incluída)');
select is((select professor_aula || ' / ' || engajamento from public.aulas_registro), 'Prof. Substituta / 4', 'os campos novos ficam gravados');
select is((select e.sigla from public.aulas_registro r join public.escolas e on e.id = r.escola_id), 'Aaa', 'escola e oficineiro preenchidos sozinhos');
select throws_ok($$insert into public.aulas_registro (grade_aula_id, data, inicio, fim, turma, tipo, situacao)
                   select g.id, d.d, g.inicio, g.fim, '4º ano · Turma A', g.tipo, 'Realizada' from public.grade_aulas g, dia d where g.ano = 4$$,
                 '42501', null, 'não registra aula da grade em dia da semana diferente');
select throws_ok($$insert into public.aulas_registro (data, inicio, fim, turma, tipo, situacao)
                   select d.d + 40, '10:00', '10:50', '3º ano · Turma B', 'R', 'Realizada' from dia d$$,
                 '42501', null, 'não registra aula de data futura');
select lives_ok($$update public.aulas_registro set presentes = 23, mudanca = null$$, 'edita o próprio registro dentro do prazo');
reset role;

create temp table grade_a as select min(id) as id from public.grade_aulas;
grant select on grade_a to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
set local role authenticated;
select throws_ok($$insert into public.aulas_registro (grade_aula_id, data, inicio, fim, turma, tipo, situacao)
                   select (select id from grade_a), d.d, '07:50', '09:30', '3º ano · Turma B', 'R', 'Realizada' from dia d$$,
                 '42501', null, 'não registra usando a grade de outra pessoa');
select is((select count(*)::int from public.aulas_registro), 0, 'não vê o registro de outra pessoa');
reset role;

select is((select presentes::int from public.aulas_registro), 23, 'a edição ficou gravada');

select * from finish();
rollback;
