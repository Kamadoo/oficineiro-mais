begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

insert into public.carteiras values ('SI1', 'SI1 - Teste');
insert into public.escolas (sigla, nome, carteira_id, latitude, longitude, raio_m) values ('Sin', 'Sin - Escola S', 'SI1', -20.0, -43.8, 150);
insert into auth.users (id, email, encrypted_password) values
  ('00000000-0000-0000-0000-0000000005a1', 'sem.internet@exemplo.test', 'hash');
insert into public.perfis (id, nome, papel, escola_id, usuario, trocar_senha, turno) values
  ('00000000-0000-0000-0000-0000000005a1', 'Oficineiro Sem Internet', 'oficineiro', (select id from public.escolas where sigla = 'Sin'),
   'of.semnet', false, 'manha');

create function pg_temp.como(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
$$;
grant execute on function pg_temp.como(text) to authenticated;

select ok(not has_function_privilege('anon', 'public.marcar_presenca(text, double precision, double precision, integer, timestamptz)', 'EXECUTE'),
          'visitante não marca presença');

select pg_temp.como('00000000-0000-0000-0000-0000000005a1');
set local role authenticated;
select throws_ok($$select public.marcar_presenca('entrada', -20.0, -43.8, 10, now() + interval '10 minutes')$$, '22023', null,
                 'hora no futuro é recusada');
select throws_ok($$select public.marcar_presenca('entrada', -20.0, -43.8, 10, now() - interval '9 hours')$$, '22023', null,
                 'marcação com mais de 8 horas é recusada');
select is((select public.marcar_presenca('entrada', -20.01, -43.8, 10, now() - interval '3 hours') ->> 'motivo'), 'Fora do raio da escola',
          'fora do raio continua recusado sem internet');
select is((select (public.marcar_presenca('entrada', -20.0, -43.8, 10, now() - interval '3 hours') ->> 'sem_internet')::boolean), true,
          'entrada feita sem internet é aceita');
select throws_ok($$select public.marcar_presenca('saida_almoco', -20.0, -43.8, 10, now() - interval '4 hours')$$, '22023',
                 'a marcação precisa ser posterior à anterior', 'marcação anterior à última é recusada');
select is((select (public.marcar_presenca('saida_almoco', -20.0, -43.8, 10, now() - interval '1 hour') ->> 'aceita')::boolean), true,
          'saída para almoço sem internet');
select is((select (public.marcar_presenca('retorno_almoco', -20.0, -43.8, 10) ->> 'sem_internet')::boolean), false,
          'marcação com internet segue com a hora do servidor');
reset role;

select ok((select abs(extract(epoch from inicio - (now() - interval '3 hours'))) < 1 from public.presencas
            where oficineiro_id = '00000000-0000-0000-0000-0000000005a1'), 'a entrada fica com a hora do aparelho');
select ok((select sem_internet and diferenca_relogio_s between 10790 and 10810 from public.presenca_marcacoes
            where oficineiro_id = '00000000-0000-0000-0000-0000000005a1' and tipo = 'entrada'),
          'marcação sem internet fica identificada com o atraso do envio');
select ok((select not sem_internet and diferenca_relogio_s is null from public.presenca_marcacoes
            where oficineiro_id = '00000000-0000-0000-0000-0000000005a1' and tipo = 'retorno_almoco'),
          'marcação com internet não fica identificada');
select is((select count(*)::int from public.presenca_tentativas where oficineiro_id = '00000000-0000-0000-0000-0000000005a1'), 1,
          'tentativa fora do raio fica guardada');

select * from finish();
rollback;
