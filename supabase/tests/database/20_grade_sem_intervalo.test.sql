begin;
create extension if not exists pgtap with schema extensions;
select plan(6);

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Aaa', 'Aaa - Escola A', 'CS1');
insert into auth.users (id, email, encrypted_password) values ('00000000-0000-0000-0000-0000000000a1', 'of.a@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000000a1', 'Oficineiro A', 'oficineiro', (select id from public.escolas), 'of.a', false);
insert into public.grade_aulas (oficineiro_id, escola_id, ano_letivo, dia_semana, inicio, fim, ano, turma, tipo, solucao) values
  ('00000000-0000-0000-0000-0000000000a1', (select id from public.escolas), 2026, 1, '08:40', '09:30', 3, 'A', 'R', 'Matific'),
  ('00000000-0000-0000-0000-0000000000a1', (select id from public.escolas), 2026, 1, '09:50', '10:40', 3, 'B', 'R', 'Matific'),
  ('00000000-0000-0000-0000-0000000000a1', (select id from public.escolas), 2026, 1, '10:40', '11:30', 3, 'C', 'R', 'Matific'),
  ('00000000-0000-0000-0000-0000000000a1', (select id from public.escolas), 2026, 2, '08:40', '10:40', 4, 'A', 'P', 'Construtores'),
  ('00000000-0000-0000-0000-0000000000a1', (select id from public.escolas), 2026, 3, '15:50', '17:30', 5, 'A', 'P', 'Projeto');
insert into public.grade_envios (oficineiro_id, escola_id, ano_letivo, status) values ('00000000-0000-0000-0000-0000000000a1', (select id from public.escolas), 2026, 'validada');

create function pg_temp.migrar() returns void language plpgsql as $f$
begin
  execute $q$alter table public.grade_aulas disable trigger grade_sem_conflito$q$;
  execute $q$alter table public.grade_aulas disable trigger grade_alterada$q$;
  execute $q$update public.grade_aulas
   set inicio = case when inicio in ('09:50', '10:40', '15:50', '16:40') then inicio - interval '20 minutes' else inicio end,
       fim    = case when fim in ('10:40', '11:30', '16:40', '17:30') then fim - interval '20 minutes' else fim end
 where inicio in ('09:50', '10:40', '15:50', '16:40')
    or fim in ('10:40', '11:30', '16:40', '17:30')$q$;
  execute $q$alter table public.grade_aulas enable trigger grade_sem_conflito$q$;
  execute $q$alter table public.grade_aulas enable trigger grade_alterada$q$;
end $f$;
select pg_temp.migrar();

select is((select string_agg(turma || ' ' || to_char(inicio, 'HH24:MI') || '-' || to_char(fim, 'HH24:MI'), ', ' order by dia_semana, inicio) from public.grade_aulas where dia_semana = 1),
          'A 08:40-09:30, B 09:30-10:20, C 10:20-11:10', 'aulas depois do intervalo sobem 20 minutos, sem sobrepor');
select is((select to_char(inicio, 'HH24:MI') || '-' || to_char(fim, 'HH24:MI') from public.grade_aulas where dia_semana = 2), '08:40-10:20', 'aula que atravessava o intervalo encolhe 20 minutos');
select is((select to_char(inicio, 'HH24:MI') || '-' || to_char(fim, 'HH24:MI') from public.grade_aulas where dia_semana = 3), '15:30-17:10', 'tarde também perde o intervalo');
select is((select status from public.grade_envios), 'validada', 'grade validada continua validada');

select pg_temp.migrar();
select is((select string_agg(to_char(inicio, 'HH24:MI'), ',' order by dia_semana, inicio) from public.grade_aulas), '08:40,09:30,10:20,08:40,15:30', 'rodar de novo não muda nada');
select throws_ok($$insert into public.grade_aulas (oficineiro_id, escola_id, ano_letivo, dia_semana, inicio, fim, ano, turma, tipo, solucao, componente)
  values ('00000000-0000-0000-0000-0000000000a1', (select id from public.escolas), 2026, 1, '09:30', '10:20', 2, 'A', 'R', 'Matific', 'Matemática')$$, '22023', null, 'conferência de conflito volta a funcionar');

select * from finish();
rollback;
