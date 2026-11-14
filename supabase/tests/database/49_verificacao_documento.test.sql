begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

insert into public.carteiras values ('VD1', 'VD1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Evd', 'Evd - Escola Verificação', 'VD1');
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000005c1', 'verifica.doc@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha, turno) values
  ('00000000-0000-0000-0000-0000000005c1', 'Ana Maria Exemplo', 'oficineiro', (select id from public.escolas where sigla = 'Evd'),
   'of.verifica', false, 'manha');
insert into public.relatorios_mensais (oficineiro_id, escola_id, competencia, status) values
  ('00000000-0000-0000-0000-0000000005c1', (select id from public.escolas where sigla = 'Evd'), '2026-10-01', 'aprovado_direcao');

select ok((select codigo_verificacao ~ '^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$' from public.relatorios_mensais
            where oficineiro_id = '00000000-0000-0000-0000-0000000005c1'), 'todo relatório recebe um código de verificação');
select ok(has_function_privilege('anon', 'public.verificar_documento(text)', 'EXECUTE'), 'visitante consulta o código');
select ok(not has_function_privilege('anon', 'privado.novo_codigo_verificacao()', 'EXECUTE'), 'visitante não gera códigos');

create temp table codigo as
  select codigo_verificacao as c from public.relatorios_mensais where oficineiro_id = '00000000-0000-0000-0000-0000000005c1';
grant select on codigo to anon;

set local role anon;
select is((select (public.verificar_documento((select c from codigo)) ->> 'encontrado')::boolean), true, 'código válido é encontrado');
select is((select public.verificar_documento(lower(replace((select c from codigo), '-', ' '))) ->> 'status'), 'aprovado_direcao',
          'o código aceita minúsculas e espaços');
select is((select public.verificar_documento((select c from codigo)) ->> 'pessoa'), 'Ana E.', 'o nome aparece abreviado');
select is((select (public.verificar_documento('AAAA-AAAA-AAAA') ->> 'encontrado')::boolean), false, 'código inexistente não é encontrado');
select is((select public.verificar_documento('x') ->> 'escola'), null, 'código malformado não revela dados');
reset role;

select * from finish();
rollback;
