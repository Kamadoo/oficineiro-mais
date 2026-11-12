begin;
create extension if not exists pgtap with schema extensions;
select plan(3);

select ok(has_table_privilege('service_role', 'public.perfis', 'INSERT'), 'função de contas grava o perfil da conta nova');
select ok(has_table_privilege('service_role', 'public.perfis', 'UPDATE'), 'função de contas atualiza o perfil');
select ok(has_table_privilege('service_role', 'public.escolas', 'SELECT') and has_table_privilege('service_role', 'public.carteiras', 'SELECT'),
          'função de contas confere escola e carteira');

select * from finish();
rollback;
