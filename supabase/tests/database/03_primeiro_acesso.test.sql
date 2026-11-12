begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

insert into public.carteiras values ('CS1', 'CS1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Aaa', 'Aaa - Escola Teste', 'CS1');
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000000c1', 'novo@exemplo.test', 'hash-inicial'),
  ('00000000-0000-0000-0000-0000000000c2', 'outro@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel) values ('00000000-0000-0000-0000-0000000000c1', 'Gerente Novo', 'gerente');
insert into public.perfis (id, nome, papel, usuario, trocar_senha) values ('00000000-0000-0000-0000-0000000000c2', 'Outro', 'gerente', 'maria.souza', false);

create function pg_temp.como(p_uid text, p_aal text default 'aal2') returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
$$;
grant execute on function pg_temp.como(text, text) to authenticated;

select is((select trocar_senha from public.perfis where id = '00000000-0000-0000-0000-0000000000c1'), true, 'conta nova nasce bloqueada (primeiro acesso)');

select pg_temp.como('00000000-0000-0000-0000-0000000000c1', 'aal1');
set local role authenticated;
select is((public.meu_acesso() ->> 'precisa_mfa')::boolean, true, 'primeiro passo: autenticador');
select throws_ok($$select public.gerar_meu_usuario()$$, '42501', null, 'sem MFA não gera usuário');
reset role;

select pg_temp.como('00000000-0000-0000-0000-0000000000c1', 'aal2');
set local role authenticated;
select is((public.meu_acesso() ->> 'precisa_criar_usuario')::boolean, true, 'depois do MFA: pede usuário');
select is((select count(*)::int from public.escolas), 0, 'antes de criar usuário e senha: não vê nada');
select is(public.gerar_meu_usuario(), 'gerente.gerente', 'usuário gerado com o cargo e o primeiro nome');
select is(public.gerar_meu_usuario(), 'gerente.gerente', 'gerar de novo devolve o mesmo usuário');
select is((public.meu_acesso() ->> 'precisa_criar_usuario')::boolean, false, 'depois de gerado, não pede usuário');
select is(public.meu_acesso() ->> 'usuario', 'gerente.gerente', 'usuário aparece no acesso para ser mostrado na tela');
select throws_ok($$update public.perfis set trocar_senha = false$$, '42501', null, 'o próprio usuário não desliga a marca');
reset role;

update auth.users set encrypted_password = 'hash-novo' where id = '00000000-0000-0000-0000-0000000000c1';
select is((select trocar_senha from public.perfis where id = '00000000-0000-0000-0000-0000000000c1'), false, 'usuário criado + senha trocada: conta liberada');

select pg_temp.como('00000000-0000-0000-0000-0000000000c1', 'aal2');
set local role authenticated;
select is((select count(*)::int from public.escolas), 1, 'conta liberada e com MFA: vê as escolas');
reset role;

select is((select bool_and(public.fsm_tentativa('cpf:teste', 5, 900)) from generate_series(1, 5)), true, '5 tentativas permitidas');
select is(public.fsm_tentativa('cpf:teste', 5, 900), false, 'a 6ª tentativa em 15 minutos é bloqueada');

select * from finish();
rollback;
