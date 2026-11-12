begin;
create extension if not exists pgtap with schema extensions;
select plan(40);

create or replace function privado.hoje() returns date language sql stable set search_path = ''
  as $$ select coalesce(nullif(current_setting('t.hoje', true), '')::date, (now() at time zone 'America/Sao_Paulo')::date) $$;
select set_config('t.hoje', '2026-10-21', true);

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Aaa', 'Aaa - Escola A', 'CS1'), ('Bbb', 'Bbb - Escola B', 'CS1');
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000000a0', 'adm@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000a9', 'adm2@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000c1', 'co@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000d1', 'ge@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000f1', 'of@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000f2', 'of2@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000000a0', 'Administração TI', 'administrador', 'adm.ti', false),
  ('00000000-0000-0000-0000-0000000000a9', 'Outra Administração', 'administrador', 'adm.dois', false),
  ('00000000-0000-0000-0000-0000000000c1', 'Coordenação', 'coordenador', 'co.x', false),
  ('00000000-0000-0000-0000-0000000000d1', 'Gerência', 'gerente', 'ge.x', false);
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000000f1', 'Oficineiro F', 'oficineiro', (select id from public.escolas where sigla = 'Aaa'), 'of.f', false),
  ('00000000-0000-0000-0000-0000000000f2', 'Oficineiro G', 'oficineiro', (select id from public.escolas where sigla = 'Aaa'), 'of.g', false);
insert into public.turmas (escola_id, ano, turma) values ((select id from public.escolas where sigla = 'Aaa'), 3, 'A');
insert into public.grade_aulas (oficineiro_id, escola_id, ano_letivo, dia_semana, inicio, fim, ano, turma, tipo, solucao, componente)
  values ('00000000-0000-0000-0000-0000000000f2', (select id from public.escolas where sigla = 'Aaa'), 2026, 1, '07:00', '07:50', 3, 'A', 'R', 'Matific', 'Matemática');

create function pg_temp.como(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;
grant execute on function pg_temp.como(text) to authenticated;
create function pg_temp.perfil(p_id uuid) returns text language sql security definer as $$
  select papel::text || ' ' || coalesce(escola_id::text, '-') || ' ' || coalesce(carteira_id, '-') || ' ' || trocar_senha from public.perfis where id = p_id;
$$;
grant execute on function pg_temp.perfil(uuid) to authenticated;
create temp table esc as select (select id from public.escolas where sigla = 'Aaa') a, (select id from public.escolas where sigla = 'Bbb') b;
grant select on esc to authenticated;

select throws_ok($$insert into public.perfis (id, nome, papel, escola_id, usuario) values ('00000000-0000-0000-0000-0000000000f2', 'X', 'administrador', 1, 'x.y')$$,
  '23514', null, 'administrador não pode ter escola');

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
set local role authenticated;
select is(privado.eh_admin(), false, 'coordenador não é administrador');
select ok((select count(*) from public.contas_gestao() where papel = 'administrador') = 0, 'coordenador não vê contas de administrador');
select throws_ok($$select public.admin_alterar_papel('00000000-0000-0000-0000-0000000000f1', 'direcao', (select a from esc), null, 'Mudança de função na escola')$$, '42501', null, 'coordenador não altera perfil');
select throws_ok($$select public.admin_salvar_escola(null, 'Zzz', 'Zzz - Escola Z', null, null, null, null, null, 80::smallint, true)$$, '42501', null, 'coordenador não cria escola');
select throws_ok($$select * from public.admin_auditoria()$$, '42501', null, 'coordenador não consulta a auditoria completa');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000a0');
set local role authenticated;
select is(privado.eh_admin(), true, 'administrador reconhecido');
select is(privado.papel_atual()::text, 'coordenador', 'administrador tem as permissões da coordenação');
select is(privado.ve_tudo(), true, 'administrador vê toda a rede');
select is(public.meu_acesso() ->> 'papel', 'administrador', 'o site recebe o cargo de administrador');
select ok((select count(*) from public.contas_gestao() where papel = 'administrador') = 2, 'administrador vê as contas de administrador');
select lives_ok($$select privado.definir_raio_escola((select a from esc), 120::smallint)$$, 'administrador faz o que a coordenação faz');
select throws_ok($$select public.revelar_cpf(1)$$, '42501', null, 'CPF completo continua só com a gerência');

select throws_ok($$select public.admin_alterar_papel('00000000-0000-0000-0000-0000000000f1', 'direcao', (select a from esc), null, 'curto')$$, '22023', null, 'motivo curto é recusado');
select throws_ok($$select public.admin_alterar_papel('00000000-0000-0000-0000-0000000000a0', 'gerente', null, null, 'Teste de alteração da própria conta')$$, '22023', null, 'não altera a própria conta');
select throws_ok($$select public.admin_alterar_papel('00000000-0000-0000-0000-0000000000a9', 'gerente', null, null, 'Teste de alteração de outro administrador')$$, '22023', null, 'não altera outro administrador pelo site');
select throws_ok($$select public.admin_alterar_papel('00000000-0000-0000-0000-0000000000f1', 'administrador', null, null, 'Promover a administrador pelo site')$$, '22023', null, 'ninguém vira administrador pelo site');
select throws_ok($$select public.admin_alterar_papel('00000000-0000-0000-0000-0000000000f1', 'direcao', null, null, 'Direção sem escola informada')$$, '22023', null, 'direção exige escola');
select lives_ok($$select public.admin_alterar_papel('00000000-0000-0000-0000-0000000000f1', 'direcao', (select b from esc), null, 'Assumiu a direção da Escola B')$$, 'muda oficineiro para direção de outra escola');
select is(pg_temp.perfil('00000000-0000-0000-0000-0000000000f1'), 'direcao ' || (select b from esc) || ' - false', 'perfil e escola gravados');
select lives_ok($$select public.admin_alterar_papel('00000000-0000-0000-0000-0000000000f1', 'analista', null, 'CS1', 'Passou a acompanhar a carteira CS1')$$, 'muda para analista com carteira');
select is(pg_temp.perfil('00000000-0000-0000-0000-0000000000f1'), 'analista - CS1 false', 'escola limpa e carteira gravada');
select throws_ok($$select public.admin_alterar_papel('00000000-0000-0000-0000-0000000000f1', 'analista', null, 'CS1', 'Mesma situação de antes')$$, '22023', null, 'sem mudança é recusado');
select lives_ok($$select public.admin_alterar_papel('00000000-0000-0000-0000-0000000000c1', 'gerente', null, null, 'Assumiu a gerência do projeto')$$, 'administrador altera coordenação e gerência');

select lives_ok($$select public.admin_exigir_troca_senha('00000000-0000-0000-0000-0000000000f2', 'Senha compartilhada por engano')$$, 'exige troca de senha');
select is(pg_temp.perfil('00000000-0000-0000-0000-0000000000f2'), 'oficineiro ' || (select a from esc) || ' - true', 'conta passa a precisar trocar a senha');
select throws_ok($$select public.admin_exigir_troca_senha('00000000-0000-0000-0000-0000000000f2', 'Senha compartilhada por engano')$$, '22023', null, 'não repete a exigência');

select lives_ok($$select public.admin_salvar_escola(null, 'Zzz', 'Zzz - Escola Z', 'Rua Teste, 10', '(31) 3333-4444', 'CS1', -20.0, -43.8, 100::smallint, true)$$, 'cria escola');
select is((select nome || ' ' || telefone || ' ' || raio_m || ' ' || posicao_confirmada from public.escolas where sigla = 'Zzz'), 'Zzz - Escola Z 3133334444 100 true', 'escola criada com telefone, raio e posição');
select throws_ok($$select public.admin_salvar_escola(null, 'aaa', 'Outra escola', null, null, null, null, null, 80::smallint, true)$$, '22023', null, 'sigla repetida é recusada');
select throws_ok($$select public.admin_salvar_escola((select a from esc), 'Aaa', 'Aaa - Escola A', null, null, 'CS1', null, null, 80::smallint, false)$$, '22023', null, 'não desativa escola com contas ativas');
select lives_ok($$select public.admin_salvar_escola((select id from public.escolas where sigla = 'Zzz'), 'Zzz', 'Zzz - Escola Zeta', null, null, null, null, null, 150::smallint, false)$$, 'edita e desativa escola sem contas');
select is((select nome || ' ' || ativa || ' ' || (latitude is null) from public.escolas where sigla = 'Zzz'), 'Zzz - Escola Zeta false true', 'edição gravada');

select lives_ok($$select public.admin_salvar_turma((select a from esc), 3::smallint, 'a', 28::smallint)$$, 'atualiza matriculados de turma existente');
select is((select matriculados from public.turmas where ano = 3 and turma = 'A'), 28::smallint, 'matriculados gravados');
select throws_ok($$select public.admin_remover_turma((select id from public.turmas where ano = 3 and turma = 'A'))$$, '22023', null, 'turma na grade não é removida');
select lives_ok($$select public.admin_remover_turma(public.admin_salvar_turma((select b from esc), 5::smallint, 'C', null))$$, 'cria e remove turma fora da grade');

select lives_ok($$select public.admin_salvar_carteira('cs2', 'CS2 - Centro')$$, 'cria carteira');
select ok((select count(*) from public.admin_auditoria(p_acao => 'ADMIN_ALTERAR_PERFIL')) = 3, 'auditoria registra as alterações de perfil');
select is((select papel || ' ' || (detalhes ->> 'motivo') from public.admin_auditoria(p_acao => 'ADMIN_ALTERAR_PERFIL') order by id limit 1), 'administrador Assumiu a direção da Escola B', 'auditoria guarda quem fez e o motivo');
reset role;

select * from finish();
rollback;
