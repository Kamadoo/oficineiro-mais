begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Aaa', 'Aaa - Escola A', 'CS1');
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000000a1', 'of.a@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000a2', 'of.b@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000c1', 'co@exemplo.test', 'hash'),
  ('00000000-0000-0000-0000-0000000000d1', 'di@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000000a1', 'Oficineiro A', 'oficineiro', (select id from public.escolas), 'of.a', false),
  ('00000000-0000-0000-0000-0000000000a2', 'Oficineiro B', 'oficineiro', (select id from public.escolas), 'of.b', false),
  ('00000000-0000-0000-0000-0000000000c1', 'Coordenação', 'coordenador', null, 'co.x', false),
  ('00000000-0000-0000-0000-0000000000d1', 'Direção', 'direcao', (select id from public.escolas), 'di.x', false);

create function pg_temp.como(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;
grant execute on function pg_temp.como(text) to authenticated;

select is(privado.cnpj_normalizado('11.222.333/0001-81'), '11222333000181', 'CNPJ válido é aceito');
select is(privado.cnpj_normalizado('11.222.333/0001-82'), null, 'CNPJ com dígito errado é recusado');
select is(privado.cnpj_normalizado('00.000.000/0000-00'), null, 'CNPJ repetido é recusado');

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
set local role authenticated;
select is(public.definir_contratada('00000000-0000-0000-0000-0000000000a1', '11.222.333/0001-81'), '**.***.333/0001-**', 'coordenador grava o CNPJ e recebe só a máscara');
select is(public.definir_contratada('00000000-0000-0000-0000-0000000000a2', '529.982.247-25'), '***.982.247-**', 'contratada também pode ser CPF');
select throws_ok($$select public.definir_contratada('00000000-0000-0000-0000-0000000000a1', '123')$$, '22023', null, 'documento inválido é recusado');
select throws_ok($$select public.definir_contratada('00000000-0000-0000-0000-0000000000d1', '11.222.333/0001-81')$$, '22023', null, 'só vale para oficineiro');
select is((select string_agg(tipo || ' ' || mascara, ', ' order by tipo) from public.contratadas_gestao()), 'CNPJ **.***.333/0001-**, CPF ***.982.247-**', 'gestão vê o tipo e a máscara');
select throws_ok($$select contratada_cifrado from public.perfis$$, '42501', null, 'documento cifrado não é lido pela API');
select throws_ok($$select contratada_mascara from public.perfis$$, '42501', null, 'máscara só pela função da gestão');
reset role;

select ok((select contratada_cifrado is not null and position(convert_to('11222333', 'UTF8') in contratada_cifrado) = 0 from public.perfis where usuario = 'of.a'), 'documento gravado cifrado');
select ok(not exists (select 1 from auditoria.eventos where detalhes::text ~ 'contratada_cifrado|11222333000181'), 'auditoria não guarda o documento');

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
select is(public.minha_contratada() ->> 'documento', '11.222.333/0001-81', 'oficineiro vê o próprio CNPJ completo para o relatório');
select throws_ok($$select * from public.contratadas_gestao()$$, '42501', null, 'oficineiro não lista as contratadas');
select throws_ok($$select public.definir_contratada(auth.uid(), '529.982.247-25')$$, '42501', null, 'oficineiro não altera a contratada');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000c1');
set local role authenticated;
select is(public.definir_contratada('00000000-0000-0000-0000-0000000000a2', ''), null, 'campo vazio limpa a contratada');
reset role;
select is((select contratada_tipo from public.perfis where usuario = 'of.b'), null, 'contratada removida');

select pg_temp.como('00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
insert into public.grade_aulas (dia_semana, horario, inicio, fim, ano, turma, tipo, solucao, componente)
values (2, 1, '07:00', '07:50', 3, 'A', 'R', 'Matific', 'Matemática');
select throws_ok($$insert into public.grade_aulas (dia_semana, horario, inicio, fim, ano, turma, tipo, solucao, componente)
                   values (2, 1, '07:30', '08:20', 4, 'B', 'R', 'Matific', 'Matemática')$$, '22023', 'já existe uma atividade sua neste horário',
                 'horários sobrepostos no mesmo dia são bloqueados');
reset role;

select * from finish();
rollback;
