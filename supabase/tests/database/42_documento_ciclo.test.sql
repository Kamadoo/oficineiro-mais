begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id, latitude, longitude, raio_m) values ('Aaa', 'Aaa - Escola A', 'CS1', -20.0, -43.8, 150);
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000000f1', 'of1@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000f2', 'of2@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000f3', 'of3@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha, turno) values
  ('00000000-0000-0000-0000-0000000000f1', 'Oficineiro CPF', 'oficineiro', (select id from public.escolas where sigla = 'Aaa'), 'of.cpf', false, 'manha'),
  ('00000000-0000-0000-0000-0000000000f2', 'Oficineiro CNPJ', 'oficineiro', (select id from public.escolas where sigla = 'Aaa'), 'of.cnpj', false, 'manha'),
  ('00000000-0000-0000-0000-0000000000f3', 'Oficineiro Antigo', 'oficineiro', (select id from public.escolas where sigla = 'Aaa'), 'of.antigo', false, 'manha');

select is(privado.documento_normalizado('529.982.247-25'), '52998224725', 'CPF válido é aceito');
select is(privado.documento_normalizado('11.222.333/0001-81'), '11222333000181', 'CNPJ válido é aceito');
select is(privado.documento_normalizado('11.222.333/0001-82'), null, 'CNPJ com dígito errado é recusado');
select is(public.fsm_definir_cpf('00000000-0000-0000-0000-0000000000f1', '529.982.247-25'), '***.982.247-**', 'conta cadastrada pelo CPF');
select is(public.fsm_definir_cpf('00000000-0000-0000-0000-0000000000f2', '11.222.333/0001-81'), '**.***.333/0001-**', 'conta cadastrada pelo CNPJ');
select is((select user_id from public.fsm_conta_por_cpf('11222333000181')), '00000000-0000-0000-0000-0000000000f2'::uuid,
          'primeiro acesso encontra a conta pelo CNPJ');
select is((select user_id from public.fsm_conta_por_cpf('529.982.247-25')), '00000000-0000-0000-0000-0000000000f1'::uuid,
          'primeiro acesso encontra a conta pelo CPF');
select is((select contratada_tipo from public.perfis where id = '00000000-0000-0000-0000-0000000000f2'), 'CNPJ',
          'documento da contratada preenchido pelo cadastro');
select throws_ok($$select public.fsm_definir_cpf('00000000-0000-0000-0000-0000000000f3', '11222333000181')$$, '23505', null,
                 'mesmo CNPJ não vale para duas contas');
select is(concat_ws(' ', privado.ciclo_tipo('00000000-0000-0000-0000-0000000000f1'), privado.ciclo_tipo('00000000-0000-0000-0000-0000000000f2'),
                    privado.ciclo_tipo('00000000-0000-0000-0000-0000000000f3')), 'mensal dia21 dia21',
          'CPF fatura no mês civil; CNPJ e contas sem documento, do dia 21 ao dia 20');
select is(concat_ws(' ', privado.ciclo_inicio('2028-02-01', 'mensal'), privado.ciclo_fim('2028-02-01', 'mensal')), '2028-02-01 2028-02-29',
          'ciclo mensal vai do dia 1 ao último dia');
select is(concat_ws(' ', privado.ciclo_inicio('2028-02-01', 'dia21'), privado.ciclo_fim('2028-02-01', 'dia21')), '2028-01-21 2028-02-20',
          'ciclo do dia 21 ao dia 20 continua igual');
select is(concat_ws(' ', privado.ciclo_de('2026-11-25', 'mensal'), privado.ciclo_de('2026-11-25', 'dia21')), '2026-11-01 2026-12-01',
          'dia 25 fica no mês dele para CPF e no ciclo seguinte para CNPJ');

select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000f1', 'role', 'authenticated', 'aal', 'aal2')::text, true);
set local role authenticated;
select is(public.meu_ciclo(), 'mensal', 'oficineiro consulta o próprio ciclo');
select is((select (public.meu_espelho(date_trunc('month', privado.hoje())::date) ->> 'inicio')::date), date_trunc('month', privado.hoje())::date,
          'espelho do oficineiro com CPF começa no dia 1');
reset role;

insert into auth.users (id, email, encrypted_password) values ('00000000-0000-0000-0000-0000000000d1', 'di@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000000d1', 'Direção', 'direcao', (select id from public.escolas where sigla = 'Aaa'), 'di.x', false);
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000d1', 'role', 'authenticated', 'aal', 'aal2')::text, true);
set local role authenticated;
select is((select mascara from public.contratadas_escola() where id = '00000000-0000-0000-0000-0000000000f2'), '**.***.333/0001-**',
          'direção vê só o documento mascarado da contratada');
reset role;
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000000f1', 'role', 'authenticated', 'aal', 'aal2')::text, true);
set local role authenticated;
select throws_ok($$select * from public.contratadas_escola()$$, '42501', null, 'oficineiro não lista documentos de outros');
reset role;

select * from finish();
rollback;
