begin;
create extension if not exists pgtap with schema extensions;
select plan(4);

insert into public.carteiras values ('MF1', 'MF1 - Teste');
insert into public.escolas (sigla, nome, carteira_id) values ('Emf', 'Emf - Escola MFA', 'MF1');
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000005f1', 'leitura.mfa@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha, turno) values
  ('00000000-0000-0000-0000-0000000005f1', 'Oficineiro MFA', 'oficineiro', (select id from public.escolas where sigla = 'Emf'),
   'of.mfa', false, 'manha');
insert into public.presenca_ajustes (oficineiro_id, escola_id, data, tipo, motivo) values
  ('00000000-0000-0000-0000-0000000005f1', (select id from public.escolas where sigla = 'Emf'), '2026-11-05', 'falta',
   'Consulta médica com atestado.');
insert into public.espelho_assinaturas (oficineiro_id, competencia, assinado_em) values
  ('00000000-0000-0000-0000-0000000005f1', '2026-10-01', now());

create function pg_temp.como(p_aal text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-0000-0000-0000000005f1', 'role', 'authenticated',
                                                            'aal', p_aal)::text, true);
$$;
grant execute on function pg_temp.como(text) to authenticated;

set local role authenticated;
select pg_temp.como('aal1');
select is((select count(*)::int from public.presenca_ajustes), 0, 'sem o segundo fator o oficineiro não lê as próprias justificativas');
select is((select count(*)::int from public.espelho_assinaturas), 0, 'sem o segundo fator o oficineiro não lê a assinatura do espelho');
select pg_temp.como('aal2');
select is((select count(*)::int from public.presenca_ajustes), 1, 'com o segundo fator o oficineiro lê as próprias justificativas');
select is((select count(*)::int from public.espelho_assinaturas), 1, 'com o segundo fator o oficineiro lê a assinatura do espelho');
reset role;

select * from finish();
rollback;
