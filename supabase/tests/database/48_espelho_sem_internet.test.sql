begin;
create extension if not exists pgtap with schema extensions;
select plan(4);

select set_config('t.hoje', '2026-11-10', true);
insert into public.carteiras values ('ES1', 'ES1 - Teste');
insert into public.escolas (sigla, nome, carteira_id, latitude, longitude, raio_m) values ('Esi', 'Esi - Escola E', 'ES1', -20.0, -43.8, 150);
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000005b1', 'espelho.semnet@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha, turno) values
  ('00000000-0000-0000-0000-0000000005b1', 'Oficineiro Espelho', 'oficineiro', (select id from public.escolas where sigla = 'Esi'),
   'of.espelho', false, 'manha');
insert into public.presencas (oficineiro_id, escola_id, data, inicio, fim) values
  ('00000000-0000-0000-0000-0000000005b1', (select id from public.escolas where sigla = 'Esi'), '2026-11-09',
   '2026-11-09 07:00-03', '2026-11-09 15:00-03');
insert into public.presenca_marcacoes (presenca_id, oficineiro_id, tipo, registrado_em, sem_internet, diferenca_relogio_s) values
  ((select id from public.presencas where oficineiro_id = '00000000-0000-0000-0000-0000000005b1'),
   '00000000-0000-0000-0000-0000000005b1', 'entrada', '2026-11-09 07:00-03', true, 3600),
  ((select id from public.presencas where oficineiro_id = '00000000-0000-0000-0000-0000000005b1'),
   '00000000-0000-0000-0000-0000000005b1', 'saida', '2026-11-09 15:00-03', false, 0);

select is((select jsonb_array_length(sem_internet) from privado.espelho_dias('00000000-0000-0000-0000-0000000005b1', '2026-11-09', '2026-11-09')),
          1, 'o espelho lista só as marcações feitas sem internet');
select is((select sem_internet -> 0 ->> 'tipo' from privado.espelho_dias('00000000-0000-0000-0000-0000000005b1', '2026-11-09', '2026-11-09')),
          'entrada', 'o espelho informa o tipo da marcação');
select is((select (sem_internet -> 0 ->> 'atraso_s')::int from privado.espelho_dias('00000000-0000-0000-0000-0000000005b1', '2026-11-09', '2026-11-09')),
          3600, 'o espelho informa quanto tempo depois a marcação chegou');
select ok(not has_function_privilege('authenticated', 'privado.espelho_dias(uuid, date, date)', 'EXECUTE'),
          'os dias do espelho continuam fora do alcance direto');

select * from finish();
rollback;
