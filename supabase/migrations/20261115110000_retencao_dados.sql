alter table public.configuracoes add column if not exists retencao_anos smallint not null default 5;
alter table public.configuracoes drop constraint if exists configuracoes_retencao_anos_check;
alter table public.configuracoes add constraint configuracoes_retencao_anos_check check (retencao_anos between 5 and 50);

create or replace function auditoria.trigger_linha()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_novo jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) - 'cpf_cifrado' - 'cpf_hash' - 'contratada_cifrado' end;
  v_velho jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) - 'cpf_cifrado' - 'cpf_hash' - 'contratada_cifrado' end;
  v_det jsonb;
begin
  if tg_op = 'DELETE' and current_setting('fsm.retencao', true) = 'sim' then return old; end if;
  if tg_op = 'UPDATE' then
    select jsonb_object_agg(k, jsonb_build_object('de', v_velho -> k, 'para', v_novo -> k)) into v_det
      from jsonb_object_keys(v_novo) k where v_novo -> k is distinct from v_velho -> k;
    if v_det is null then return new; end if;
  else
    v_det := coalesce(v_novo, v_velho);
  end if;
  perform auditoria.registrar(tg_op, tg_table_name, coalesce(v_novo, v_velho) ->> 'id', v_det);
  return coalesce(new, old);
end;
$$;

create or replace function auditoria.bloquear_alteracao()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' and current_setting('fsm.retencao', true) = 'sim' then
    if old.em < now() - interval '5 years' then return old; end if;
  end if;
  raise exception 'auditoria é somente inclusão (% bloqueado)', tg_op using errcode = '42501';
end;
$$;

create or replace function privado.aplicar_retencao()
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_anos int := greatest(5, coalesce((select c.retencao_anos from public.configuracoes c order by c.id limit 1), 5));
  v_corte date := make_date(extract(year from privado.hoje())::int - v_anos, 1, 1);
  v_ano smallint := (extract(year from privado.hoje())::int - v_anos - 1)::smallint;
  v_total jsonb := '{}'::jsonb;
  v_n int;
begin
  perform set_config('fsm.retencao', 'sim', true);

  delete from public.presenca_tentativas where tentado_em < v_corte;
  get diagnostics v_n = row_count; v_total := v_total || jsonb_build_object('presenca_tentativas', v_n);
  delete from public.presencas where data < v_corte;
  get diagnostics v_n = row_count; v_total := v_total || jsonb_build_object('presencas', v_n);
  delete from public.presenca_ajustes where data < v_corte;
  get diagnostics v_n = row_count; v_total := v_total || jsonb_build_object('presenca_ajustes', v_n);
  delete from public.espelho_assinaturas where competencia < v_corte;
  get diagnostics v_n = row_count; v_total := v_total || jsonb_build_object('espelho_assinaturas', v_n);
  delete from public.relatorios_mensais where competencia < v_corte;
  get diagnostics v_n = row_count; v_total := v_total || jsonb_build_object('relatorios_mensais', v_n);
  delete from public.aulas_registro where data < v_corte;
  get diagnostics v_n = row_count; v_total := v_total || jsonb_build_object('aulas_registro', v_n);
  delete from public.lembretes_registro where data < v_corte;
  get diagnostics v_n = row_count; v_total := v_total || jsonb_build_object('lembretes_registro', v_n);
  delete from public.grade_semanas where semana < v_corte;
  get diagnostics v_n = row_count; v_total := v_total || jsonb_build_object('grade_semanas', v_n);
  delete from public.grade_envios where ano_letivo <= v_ano;
  get diagnostics v_n = row_count; v_total := v_total || jsonb_build_object('grade_envios', v_n);
  delete from public.grade_aulas where ano_letivo <= v_ano;
  get diagnostics v_n = row_count; v_total := v_total || jsonb_build_object('grade_aulas', v_n);
  delete from public.visitas where data < v_corte;
  get diagnostics v_n = row_count; v_total := v_total || jsonb_build_object('visitas', v_n);
  delete from public.presencas_analista where data < v_corte;
  get diagnostics v_n = row_count; v_total := v_total || jsonb_build_object('presencas_analista', v_n);
  delete from public.visitas_agenda where data < v_corte;
  get diagnostics v_n = row_count; v_total := v_total || jsonb_build_object('visitas_agenda', v_n);
  delete from public.mudancas_escola where vale_a_partir < v_corte;
  get diagnostics v_n = row_count; v_total := v_total || jsonb_build_object('mudancas_escola', v_n);
  delete from public.onboarding_os where recebida_em < v_corte;
  get diagnostics v_n = row_count; v_total := v_total || jsonb_build_object('onboarding_os', v_n);
  delete from public.jornada_pessoas where base_ref < v_corte;
  get diagnostics v_n = row_count; v_total := v_total || jsonb_build_object('jornada_pessoas', v_n);
  delete from auditoria.eventos where em < make_date(extract(year from now())::int - v_anos, 1, 1);
  get diagnostics v_n = row_count; v_total := v_total || jsonb_build_object('auditoria', v_n);

  perform set_config('fsm.retencao', '', true);
  perform auditoria.registrar('RETENCAO', 'varias', v_corte::text, v_total);
  return jsonb_build_object('corte', v_corte, 'apagados', v_total);
end;
$$;

revoke all on function privado.aplicar_retencao() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron with schema pg_catalog;
    perform cron.schedule('fsm-retencao-anual', '23 5 15 2 *', 'select privado.aplicar_retencao()');
  else
    raise notice 'pg_cron indisponível: a retenção dos dados não foi agendada';
  end if;
exception when others then
  raise notice 'não foi possível agendar a retenção dos dados: %', sqlerrm;
end $$;
