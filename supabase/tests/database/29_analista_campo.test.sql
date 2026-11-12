begin;
create extension if not exists pgtap with schema extensions;
select plan(34);

create or replace function privado.hoje() returns date language sql stable set search_path = ''
  as $$ select coalesce(nullif(current_setting('t.hoje', true), '')::date, (now() at time zone 'America/Sao_Paulo')::date) $$;
select set_config('t.hoje', '2026-10-21', true);

insert into public.carteiras values ('CS1', 'CS1 - Teste'), ('CS2', 'CS2 - Teste');
insert into public.escolas (sigla, nome, carteira_id, latitude, longitude, raio_m)
values ('Aaa', 'Aaa - Escola A', 'CS1', -20.0, -43.8, 150), ('Bbb', 'Bbb - Escola B', 'CS2', -19.9, -43.9, 150),
       ('Ccc', 'Ccc - Escola C', 'CS1', null, null, 150);
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
insert into public.onboarding_os (id, numero, secretaria, recebida_em) values ('SEMED-001', '001', 'SEMED', '2026-10-01');
insert into public.onboarding_itens (os_id, nome, cpf_cifrado, cpf_hash, cpf_mascara, carteira_id, status, baixa_data, baixa_forma, baixa_por)
values ('SEMED-001', 'Pessoa Um', decode('01', 'hex'), decode('01', 'hex'), '***', 'CS1', 'concluido', '2026-10-10', 'Remoto', '00000000-0000-0000-0000-0000000000b1'),
       ('SEMED-001', 'Pessoa Dois', decode('02', 'hex'), decode('02', 'hex'), '***', 'CS1', 'concluido', '2026-10-10', 'Remoto', '00000000-0000-0000-0000-0000000000a1');

create function pg_temp.como(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;
grant execute on function pg_temp.como(text) to authenticated;
create function pg_temp.esc(p_sig text) returns smallint language sql security definer as $$ select id from public.escolas where sigla = p_sig $$;
grant execute on function pg_temp.esc(text) to authenticated;

select is((select relrowsecurity from pg_class where oid = 'public.presencas_analista'::regclass), true, 'presença do analista tem RLS');

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
select lives_ok($$select public.agendar_visita('00000000-0000-0000-0000-0000000000b1', pg_temp.esc('Aaa'), '2026-10-21', '08:00', 'gerencia', 'Acompanhamento · Plano de ação', 'Professores', 'Ver o Matific')$$, 'gerente vincula visita de hoje');
select throws_ok($$select public.agendar_visita('00000000-0000-0000-0000-0000000000b1', pg_temp.esc('Aaa'), '2026-11-02', '08:00', 'gerencia')$$, '22023', 'a data escolhida é feriado', 'gerência não agenda em feriado');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
set local role authenticated;
select lives_ok($$select public.presenca_analista('inicio', pg_temp.esc('Aaa'), -20.0, -43.8, (select id from public.visitas_agenda limit 1), 'chegada')$$, 'analista inicia presença na escola da carteira');
select is((select conferencia from public.presencas_analista), null, 'dentro do raio não marca conferência');
select throws_ok($$select public.presenca_analista('inicio', pg_temp.esc('Aaa'), -20.0, -43.8)$$, '22023', 'encerre a presença em andamento antes de iniciar outra', 'não abre duas presenças');
select throws_ok($$select public.presenca_analista('fim', null, -20.05, -43.8)$$, '22023', null, 'não encerra fora do raio');
select throws_ok($$select public.presenca_analista('fim', null, null, null)$$, '22023', 'ative a localização do aparelho para registrar a presença na escola', 'não encerra sem localização');
select lives_ok($$select public.presenca_analista('fim', null, -20.0, -43.8)$$, 'analista encerra a presença');
select ok((select fim is not null from public.presencas_analista), 'encerramento gravado');
select throws_ok($$select public.presenca_analista('inicio', pg_temp.esc('Aaa'), -20.05, -43.8)$$, '22023', null, 'não inicia longe da escola');
select throws_ok($$select public.presenca_analista('inicio', pg_temp.esc('Aaa'), null, null)$$, '22023', 'ative a localização do aparelho para registrar a presença na escola', 'não inicia sem localização');
select throws_ok($$select public.presenca_analista('inicio', pg_temp.esc('Ccc'), -20.0, -43.8)$$, '22023', 'a escola ainda não tem localização cadastrada; peça ao coordenador para cadastrar', 'não inicia em escola sem localização');
select is((select count(*)::int from public.presencas_analista where fim is null), 0, 'nenhuma presença fora do perímetro foi aberta');
select throws_ok($$select public.presenca_analista('inicio', pg_temp.esc('Bbb'), -19.9, -43.9)$$, '22023', 'esta escola não é da sua carteira', 'escola de outra carteira recusada');

select lives_ok($$select public.agendar_minha_visita(pg_temp.esc('Aaa'), '2026-10-23', '09:00', 'analista', 'Suporte · Apoio a usuários', null, null)$$, 'analista agenda visita própria');
select throws_ok($$select public.agendar_minha_visita(pg_temp.esc('Aaa'), '2026-10-24', '09:00', 'analista')$$, '22023', 'escolha um dia útil', 'não agenda no fim de semana');
select lives_ok($$select public.remarcar_visita_agenda((select id from public.visitas_agenda where origem = 'analista'), '2026-10-26', '10:00', 'Escola pediu outro dia')$$, 'remarca a própria visita');
select is((select data_original::text || ' ' || data::text from public.visitas_agenda where origem = 'analista'), '2026-10-23 2026-10-26', 'guarda a data original');
select throws_ok($$select public.cancelar_minha_visita((select id from public.visitas_agenda where origem = 'gerencia'), 'não posso')$$, '42501', null, 'não cancela visita da gerência');
select lives_ok($$select public.cancelar_minha_visita((select id from public.visitas_agenda where origem = 'analista'), 'Escola em evento')$$, 'cancela a própria visita');

select lives_ok($$select public.registrar_visita(jsonb_build_object('escola', pg_temp.esc('Aaa'), 'data', '2026-10-21', 'tipo', 'Acompanhamento', 'subtipo', 'Plano de ação', 'observacao', 'Reunião com a direção sobre o uso do Matific', 'objetivo', 'Sim', 'engajamento', 4, 'presenca_id', (select min(id) from public.presencas_analista)))$$, 'registra a visita');
select is((select status from public.visitas_agenda where origem = 'gerencia'), 'realizada', 'visita da agenda vira realizada');
select throws_ok($$select public.registrar_visita(jsonb_build_object('escola', pg_temp.esc('Aaa'), 'data', '2026-10-22', 'tipo', 'Suporte', 'observacao', 'Visita do futuro, não pode'))$$, '22023', 'a data da visita não pode ser futura', 'não registra visita futura');
select lives_ok($$select public.editar_visita((select id from public.visitas), jsonb_build_object('data', '2026-10-21', 'tipo', 'Formação', 'observacao', 'Formação com 6 professores no Matific'))$$, 'corrige a visita');
select is((select count(*)::int from public.visitas_historico), 1, 'correção guarda o histórico');
select throws_ok($$insert into public.visitas (analista_id, escola_id, data, tipo) values ('00000000-0000-0000-0000-0000000000b1', pg_temp.esc('Aaa'), '2026-10-20', 'Suporte')$$, '42501', null, 'não grava visita direto na tabela');
select lives_ok($$select public.reabrir_onboarding((select id from public.onboarding_itens where nome = 'Pessoa Um'))$$, 'analista desfaz a própria baixa');
select throws_ok($$select public.reabrir_onboarding((select id from public.onboarding_itens where nome = 'Pessoa Dois'))$$, '42501', null, 'não desfaz baixa de outra pessoa');
reset role;

insert into public.presencas_analista (analista_id, escola_id, data, inicio)
values ('00000000-0000-0000-0000-0000000000b1', pg_temp.esc('Aaa'), '2026-10-19', '2026-10-19 08:00-03');
select pg_temp.como('00000000-0000-0000-0000-0000000000b1');
set local role authenticated;
select lives_ok($$select public.presenca_analista('fim', null, -20.0, -43.8)$$, 'encerra presença esquecida de outro dia');
select is((select conferencia || ' ' || ((fim at time zone 'America/Sao_Paulo')::date)::text from public.presencas_analista where data = '2026-10-19'), 'Encerrada em outro dia 2026-10-19', 'presença esquecida fecha no próprio dia e fica para conferência');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000b2');
set local role authenticated;
select is((select count(*)::int from public.presencas_analista), 0, 'outro analista não vê a presença');
select is((select count(*)::int from public.visitas_historico), 0, 'outro analista não vê o histórico');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
select is((select count(*)::int from public.presencas_analista), 2, 'gerente vê a presença dos analistas');
reset role;

select * from finish();
rollback;
