begin;
create extension if not exists pgtap with schema extensions;
select plan(20);

insert into public.carteiras values ('CG1', 'CG1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Cga', 'Cga - Escola Cargo', 'CG1');
insert into public.turmas (escola_id, ano, turma)
select e.id, 3, 'A' from public.escolas e where e.sigla = 'Cga';
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000f1a01', 'of.id@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000f1a02', 'of.ti@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000f1b01', 'dir.cargo@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000f1c01', 'co.cargo@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000f1e01', 'an.cargo@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha)
select x.id::uuid, x.nome, x.papel::public.papel, e.id, x.usuario, false
  from (values ('00000000-0000-0000-0000-0000000f1a01', 'Oficineiro Digital', 'oficineiro', 'of.id', 'Cga'),
               ('00000000-0000-0000-0000-0000000f1a02', 'Oficineiro Oficinas', 'oficineiro', 'of.ti', 'Cga'),
               ('00000000-0000-0000-0000-0000000f1b01', 'Direção Cargo', 'direcao', 'dir.cargo', 'Cga'),
               ('00000000-0000-0000-0000-0000000f1c01', 'Coord Cargo', 'coordenador', 'co.cargo', null)) x(id, nome, papel, usuario, sig)
  left join public.escolas e on e.sigla = x.sig;
insert into public.perfis (id, nome, papel, carteira_id, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000f1e01', 'Analista Cargo', 'analista', 'CG1', 'an.cargo', false);

create function pg_temp.como(p_uid text, p_aal text default 'aal2') returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
$$;
grant execute on function pg_temp.como(text, text) to authenticated;

select is((select cargo from public.perfis where id = '00000000-0000-0000-0000-0000000f1a01'), 'inclusao_digital',
          'conta de oficineiro criada sem cargo fica como Oficineiro de Inclusão Digital');
select is((select cargo from public.perfis where id = '00000000-0000-0000-0000-0000000f1b01'), null,
          'conta de direção não tem cargo');
update public.perfis set cargo = 'tempo_integral' where id = '00000000-0000-0000-0000-0000000f1b01';
select is((select cargo from public.perfis where id = '00000000-0000-0000-0000-0000000f1b01'), null,
          'o cargo de oficineiro não é gravado em outro perfil');
select throws_ok($$update public.perfis set cargo = 'outro' where id = '00000000-0000-0000-0000-0000000f1a02'$$,
                 '23514', null, 'cargo fora da lista é recusado');

select pg_temp.como('00000000-0000-0000-0000-0000000f1a02');
set local role authenticated;
select lives_ok($$insert into public.grade_aulas (dia_semana, inicio, fim, ano, turma, tipo, solucao, componente)
                  values (2, '08:00', '08:50', 3, 'A', 'R', 'Matific', 'Matemática')$$,
                'antes da troca, o oficineiro de inclusão digital cria aula regular');
select throws_ok($$update public.perfis set cargo = 'tempo_integral' where id = '00000000-0000-0000-0000-0000000f1a02'$$,
                 '42501', null, 'o oficineiro não troca o próprio cargo');
select throws_ok($$select public.alterar_cargo('00000000-0000-0000-0000-0000000f1a02', 'tempo_integral', 'motivo de teste suficiente')$$,
                 '42501', null, 'o oficineiro não usa a troca de cargo');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000f1e01');
set local role authenticated;
select throws_ok($$select public.alterar_cargo('00000000-0000-0000-0000-0000000f1a02', 'tempo_integral', 'motivo de teste suficiente')$$,
                 '42501', null, 'o analista não troca cargo');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000f1c01');
set local role authenticated;
select throws_ok($$select public.alterar_cargo('00000000-0000-0000-0000-0000000f1a02', 'tempo_integral', 'curto')$$,
                 '22023', null, 'a troca de cargo pede motivo');
select throws_ok($$select public.alterar_cargo('00000000-0000-0000-0000-0000000f1b01', 'tempo_integral', 'motivo de teste suficiente')$$,
                 '22023', null, 'conta de direção não recebe cargo');
select throws_ok($$select public.alterar_cargo('00000000-0000-0000-0000-0000000f1a02', 'inclusao_digital', 'motivo de teste suficiente')$$,
                 '22023', null, 'troca para o mesmo cargo é recusada');
select throws_ok($$select public.alterar_cargo('00000000-0000-0000-0000-0000000f1a02', 'tempo_integral', 'motivo de teste suficiente')$$,
                 '22023', null, 'grade com aula regular impede a troca para o cargo Oficineiro');
reset role;

delete from public.grade_aulas where oficineiro_id = '00000000-0000-0000-0000-0000000f1a02';

select pg_temp.como('00000000-0000-0000-0000-0000000f1c01');
set local role authenticated;
select lives_ok($$select public.alterar_cargo('00000000-0000-0000-0000-0000000f1a02', 'tempo_integral', 'motivo de teste suficiente')$$,
                'o coordenador troca o cargo de um oficineiro');
select is((select cargo from public.contas_gestao() where id = '00000000-0000-0000-0000-0000000f1a02'), 'tempo_integral',
          'a gestão de contas mostra o cargo');
reset role;

select is((select count(*)::int from auditoria.eventos
            where acao = 'ALTERAR_CARGO' and registro = '00000000-0000-0000-0000-0000000f1a02'), 1,
          'a troca de cargo fica na auditoria');

select pg_temp.como('00000000-0000-0000-0000-0000000f1a02');
set local role authenticated;
select is(public.meu_acesso() ->> 'cargo', 'tempo_integral', 'o próprio acesso informa o cargo');
select is((select cargo from public.perfis where id = '00000000-0000-0000-0000-0000000f1a02'), 'tempo_integral',
          'o oficineiro lê o próprio cargo');
select throws_ok($$insert into public.grade_aulas (dia_semana, inicio, fim, ano, turma, tipo, solucao, componente)
                   values (3, '08:00', '08:50', 3, 'A', 'R', 'Matific', 'Matemática')$$,
                 '22023', null, 'o cargo Oficineiro não cria aula regular');
select throws_ok($$insert into public.grade_aulas (dia_semana, inicio, fim, tipo, solucao) values (3, '09:00', '09:50', 'F', 'Eduminers')$$,
                 '22023', null, 'o cargo Oficineiro não cria formação de professores');
select lives_ok($$insert into public.grade_aulas (dia_semana, inicio, fim, ano, turma, tipo, oficina)
                  values (3, '10:00', '10:50', 3, 'A', 'P', 'Artesanato')$$,
                'o cargo Oficineiro cria projeto tempo integral');
reset role;

select * from finish();
rollback;
