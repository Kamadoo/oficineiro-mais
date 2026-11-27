begin;
create extension if not exists pgtap with schema extensions;
select plan(6);

insert into public.carteiras values ('CA1', 'CA1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Caa', 'Caa - Escola Alunos', 'CA1');
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000a1a01', 'ger.os@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, usuario, trocar_senha) values
  ('00000000-0000-0000-0000-0000000a1a01', 'Gerente OS', 'gerente', 'ger.os', false);
create function pg_temp.como(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;
grant execute on function pg_temp.como(text) to authenticated;

select pg_temp.como('00000000-0000-0000-0000-0000000a1a01');
set local role authenticated;
select is(public.importar_os('{"numero":"21","secretaria":"SEMED","arquivo":"os.xlsx","recebida_em":"2026-11-27","linhas":[
            {"seq":"1","nome":"Aluno Ficticio Um","email":"aluno1@exemplo.test","cpf":"","cargo":"Aluno","escola_sigla":"Caa","carteira_id":"CA1"},
            {"seq":"2","nome":"Aluna Ficticia Dois","email":"","matricula":"778","cpf":"","cargo":"Aluna","escola_sigla":"Caa","carteira_id":"CA1"},
            {"seq":"3","nome":"Professor Sem CPF","email":"prof@exemplo.test","cpf":"","cargo":"Professor","escola_sigla":"Caa"},
            {"seq":"4","nome":"Professor Com CPF","email":"prof2@exemplo.test","cpf":"529.982.247-25","cargo":"Professor","escola_sigla":"Caa"},
            {"seq":"5","nome":"Aluno Ficticio Um","email":"ALUNO1@exemplo.test","cpf":"","cargo":"Aluno","escola_sigla":"Caa"}]}')
          - 'os' - 'duplicados',
          '{"inseridos":3,"invalidos":["3"]}'::jsonb, 'alunos entram sem CPF; outros cargos continuam exigindo CPF');
select is((select count(*)::int from public.onboarding_itens where os_id = 'SEMED-021' and cpf_mascara = 'sem CPF'), 2,
          'alunos sem CPF ficam marcados como sem CPF');
select is((select jsonb_array_length(public.importar_os('{"numero":"22","secretaria":"SEMED","linhas":[
            {"seq":"1","nome":"Aluna Ficticia Dois","matricula":"778","cargo":"Aluna"}]}') -> 'duplicados')), 1,
          'aluno sem CPF repetido em outra OS é ignorado pela matrícula');
select is((public.importar_os('{"numero":"23","secretaria":"SEMED","linhas":[
            {"seq":"1","nome":"Aluno Com CPF","cpf":"111.444.777-35","cargo":"Aluno"}]}') ->> 'inseridos')::int, 1,
          'aluno com CPF válido continua aceito');
select is((select cpf_mascara from public.onboarding_itens where nome = 'Aluno Com CPF'), '***.444.777-**', 'CPF do aluno informado continua mascarado');
reset role;
select is((select count(*)::int from public.onboarding_itens where cpf_mascara = 'sem CPF' and cpf_cifrado is null), 2, 'aluno sem CPF não guarda CPF cifrado');

select * from finish();
rollback;
