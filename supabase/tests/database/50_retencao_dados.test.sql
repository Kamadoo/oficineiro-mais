begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

create or replace function privado.hoje() returns date language sql stable set search_path = ''
  as $$ select coalesce(nullif(current_setting('t.hoje', true), '')::date, (now() at time zone 'America/Sao_Paulo')::date) $$;
select set_config('t.hoje', '2032-02-15', true);
insert into public.carteiras values ('RT1', 'RT1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Ert', 'Ert - Escola Retenção', 'RT1');
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000005d1', 'retencao@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha, turno) values
  ('00000000-0000-0000-0000-0000000005d1', 'Oficineiro Retenção', 'oficineiro', (select id from public.escolas where sigla = 'Ert'),
   'of.retencao', false, 'manha');
insert into public.presencas (oficineiro_id, escola_id, data, inicio, fim) values
  ('00000000-0000-0000-0000-0000000005d1', (select id from public.escolas where sigla = 'Ert'), '2026-11-09',
   '2026-11-09 07:00-03', '2026-11-09 15:00-03'),
  ('00000000-0000-0000-0000-0000000005d1', (select id from public.escolas where sigla = 'Ert'), '2027-03-09',
   '2027-03-09 07:00-03', '2027-03-09 15:00-03');
insert into public.relatorios_mensais (oficineiro_id, escola_id, competencia, status) values
  ('00000000-0000-0000-0000-0000000005d1', (select id from public.escolas where sigla = 'Ert'), '2026-10-01', 'aprovado_coordenacao');

select ok(not has_function_privilege('authenticated', 'privado.aplicar_retencao()', 'EXECUTE'), 'só o agendamento aplica a retenção');

create temp table antes as select coalesce(max(id), 0) as n from auditoria.eventos;
select is((select (privado.aplicar_retencao() ->> 'corte')), '2027-01-01', 'o corte é o início do ano de cinco anos atrás');
select is((select count(*)::int from public.presencas where oficineiro_id = '00000000-0000-0000-0000-0000000005d1' and data < '2027-01-01'), 0,
          'presenças do ano letivo vencido são apagadas');
select is((select count(*)::int from public.presencas where oficineiro_id = '00000000-0000-0000-0000-0000000005d1' and data >= '2027-01-01'), 1,
          'presenças dentro do prazo continuam');
select is((select count(*)::int from public.relatorios_mensais where oficineiro_id = '00000000-0000-0000-0000-0000000005d1'), 0,
          'relatórios vencidos são apagados');
select is((select count(*)::int from auditoria.eventos where id > (select n from antes) and acao = 'DELETE'), 0,
          'a auditoria não copia as linhas apagadas');
update public.configuracoes set retencao_anos = 6;
select is((select (privado.aplicar_retencao() ->> 'corte')), '2026-01-01', 'o prazo vem das configurações');

select * from finish();
rollback;
