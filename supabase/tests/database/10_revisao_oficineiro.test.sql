begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Aaa', 'Aaa - Escola A', 'CS1');
insert into auth.users (id, email, encrypted_password) values ('00000000-0000-0000-0000-0000000000a1', 'of.a@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha)
select '00000000-0000-0000-0000-0000000000a1', 'Oficineiro A', 'oficineiro', id, 'of.a', false from public.escolas;

create temp table dia as
select max(x)::date as d from generate_series(privado.ciclo_inicio(privado.ciclo_de(privado.hoje())), privado.hoje(), interval '1 day') x where extract(isodow from x) <= 5;
grant select on dia to authenticated;
insert into public.presencas (oficineiro_id, escola_id, data, inicio, fim)
select p.id, p.escola_id, d, (d + time '07:00') at time zone 'America/Sao_Paulo', (d + time '12:00') at time zone 'America/Sao_Paulo'
  from dia, public.perfis p where p.id = '00000000-0000-0000-0000-0000000000a1';

create function pg_temp.como(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;
grant execute on function pg_temp.como(text) to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
select throws_ok($$insert into public.grade_aulas (ano_letivo, dia_semana, inicio, fim, ano, turma, tipo, solucao, componente)
                   values (extract(year from privado.hoje())::smallint + 5, 1, '07:00', '07:50', 3, 'A', 'R', 'Matific', 'Matemática')$$,
                 '42501', null, 'não cria grade para anos distantes');
select lives_ok($$insert into public.grade_aulas (ano_letivo, dia_semana, inicio, fim, ano, turma, tipo, solucao, componente)
                  values (extract(year from privado.hoje())::smallint + 1, 1, '07:00', '07:50', 3, 'A', 'R', 'Matific', 'Matemática')$$,
                'pode montar a grade do próximo ano');
insert into public.grade_aulas (dia_semana, inicio, fim, ano, turma, tipo, oficina)
select extract(isodow from d), '07:50', '09:30', 3, 'B', 'P', 'Programa Construtores – Minecraft' from dia;
insert into public.aulas_registro (grade_aula_id, data, inicio, fim, turma, tipo, situacao, presentes, conteudo)
select g.id, d.d, '13:00', '13:10', 'Turma inventada', 'R', 'Realizada', 20, 'Aula sobre construção coletiva.'
  from public.grade_aulas g, dia d where g.turma = 'B';
select is((select inicio::text || ' ' || fim::text || ' ' || tipo || ' ' || turma from public.aulas_registro),
          '07:50:00 09:30:00 P 3º ano · Turma B', 'horário, tipo e turma do registro vêm da grade, não do que o site mandou');
select lives_ok($$delete from public.grade_aulas where turma = 'B'$$, 'excluir a aula da grade não trava');
select is((select count(*)::int from public.aulas_registro where grade_aula_id is null), 1, 'o registro antigo continua guardado');
select throws_ok($$select public.fechar_relatorio(privado.ciclo_de(privado.hoje()))$$, '22023', null, 'o ciclo atual não pode ser fechado pelo oficineiro');
select lives_ok($$select public.fechar_relatorio((privado.ciclo_de(privado.hoje()) - interval '1 month')::date)$$, 'o ciclo anterior pode ser enviado');
reset role;

select * from finish();
rollback;
