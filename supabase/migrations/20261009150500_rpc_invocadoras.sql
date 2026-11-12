grant usage on schema privado to service_role;

do $$
declare
  f text;
begin
  foreach f in array array[
    'registrar_presenca(text, double precision, double precision, timestamptz)',
    'justificar_presenca(bigint, text, text)',
    'decidir_excedente(bigint, boolean)',
    'conferir_aula(bigint, boolean, text)',
    'fechar_relatorio(date)',
    'aprovar_relatorio(bigint)',
    'devolver_relatorio(bigint, text)',
    'importar_os(jsonb)',
    'dar_baixa_onboarding(bigint, date, text, text)',
    'reabrir_onboarding(bigint)',
    'atribuir_onboarding(bigint, text)',
    'revelar_cpf(bigint)',
    'auditoria_recente(integer)',
    'meu_acesso()'
  ] loop
    if exists (select 1 from pg_proc where oid = to_regprocedure('public.' || f) and prosecdef) then
      execute 'alter function public.' || f || ' set schema privado';
    end if;
  end loop;
end $$;

create or replace function public.registrar_presenca(p_evento text, p_lat double precision, p_lng double precision, p_quando timestamptz default null)
returns jsonb language sql security invoker set search_path = ''
as $$ select privado.registrar_presenca(p_evento, p_lat, p_lng, p_quando) $$;

create or replace function public.justificar_presenca(p_id bigint, p_motivo text, p_justificativa text)
returns void language sql security invoker set search_path = ''
as $$ select privado.justificar_presenca(p_id, p_motivo, p_justificativa) $$;

create or replace function public.decidir_excedente(p_id bigint, p_autorizar boolean)
returns void language sql security invoker set search_path = ''
as $$ select privado.decidir_excedente(p_id, p_autorizar) $$;

create or replace function public.conferir_aula(p_id bigint, p_confirmar boolean, p_motivo text default null)
returns void language sql security invoker set search_path = ''
as $$ select privado.conferir_aula(p_id, p_confirmar, p_motivo) $$;

create or replace function public.fechar_relatorio(p_competencia date)
returns bigint language sql security invoker set search_path = ''
as $$ select privado.fechar_relatorio(p_competencia) $$;

create or replace function public.aprovar_relatorio(p_id bigint)
returns void language sql security invoker set search_path = ''
as $$ select privado.aprovar_relatorio(p_id) $$;

create or replace function public.devolver_relatorio(p_id bigint, p_motivo text)
returns void language sql security invoker set search_path = ''
as $$ select privado.devolver_relatorio(p_id, p_motivo) $$;

create or replace function public.importar_os(p_os jsonb)
returns jsonb language sql security invoker set search_path = ''
as $$ select privado.importar_os(p_os) $$;

create or replace function public.dar_baixa_onboarding(p_id bigint, p_data date, p_forma text, p_obs text default null)
returns void language sql security invoker set search_path = ''
as $$ select privado.dar_baixa_onboarding(p_id, p_data, p_forma, p_obs) $$;

create or replace function public.reabrir_onboarding(p_id bigint)
returns void language sql security invoker set search_path = ''
as $$ select privado.reabrir_onboarding(p_id) $$;

create or replace function public.atribuir_onboarding(p_id bigint, p_carteira text)
returns void language sql security invoker set search_path = ''
as $$ select privado.atribuir_onboarding(p_id, p_carteira) $$;

create or replace function public.revelar_cpf(p_id bigint)
returns text language sql security invoker set search_path = ''
as $$ select privado.revelar_cpf(p_id) $$;

create or replace function public.auditoria_recente(p_limite integer default 100)
returns table (id bigint, em timestamptz, usuario_id uuid, papel text, aal text, acao text, tabela text, registro text, detalhes jsonb)
language sql security invoker set search_path = ''
as $$ select e.id, e.em, e.usuario_id, e.papel, e.aal, e.acao, e.tabela, e.registro, e.detalhes
        from privado.auditoria_recente(p_limite) e $$;

create or replace function public.meu_acesso()
returns jsonb language sql stable security invoker set search_path = ''
as $$ select privado.meu_acesso() $$;

do $$
declare f text;
begin
  foreach f in array array[
    'registrar_presenca(text, double precision, double precision, timestamptz)',
    'justificar_presenca(bigint, text, text)', 'decidir_excedente(bigint, boolean)',
    'conferir_aula(bigint, boolean, text)', 'fechar_relatorio(date)', 'aprovar_relatorio(bigint)',
    'devolver_relatorio(bigint, text)', 'importar_os(jsonb)', 'dar_baixa_onboarding(bigint, date, text, text)',
    'reabrir_onboarding(bigint)', 'atribuir_onboarding(bigint, text)', 'revelar_cpf(bigint)',
    'auditoria_recente(integer)', 'meu_acesso()'
  ] loop
    execute 'revoke all on function public.' || f || ' from public, anon';
    execute 'revoke all on function privado.' || f || ' from public, anon';
    execute 'grant execute on function public.' || f || ' to authenticated';
    execute 'grant execute on function privado.' || f || ' to authenticated';
  end loop;
end $$;
grant execute on function public.importar_os(jsonb), privado.importar_os(jsonb) to service_role;
