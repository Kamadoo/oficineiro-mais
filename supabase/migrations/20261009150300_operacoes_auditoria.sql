create or replace function privado.negar(p_msg text default 'sem permissão para esta operação')
returns void language plpgsql set search_path = ''
as $$ begin raise exception '%', p_msg using errcode = '42501'; end; $$;

create or replace function privado.invalido(p_msg text)
returns void language plpgsql set search_path = ''
as $$ begin raise exception '%', p_msg using errcode = '22023'; end; $$;

revoke all on function privado.negar(text), privado.invalido(text) from public, anon;

create or replace function privado.distancia_m(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision)
returns integer language sql immutable set search_path = ''
as $$
  select round(2 * 6371000 * asin(sqrt(
           power(sin(radians(lat2 - lat1) / 2), 2) +
           cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2))))::integer;
$$;
revoke all on function privado.distancia_m(double precision, double precision, double precision, double precision) from public, anon;

create or replace function public.registrar_presenca(
  p_evento     text,
  p_lat        double precision,
  p_lng        double precision,
  p_quando     timestamptz default null
)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_esc public.escolas;
  v_quando timestamptz := now();
  v_conf text;
  v_dist integer;
  v_data date;
  v_p public.presencas;
  v_min integer;
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  if p_evento not in ('inicio', 'fim') then perform privado.invalido('evento deve ser inicio ou fim'); end if;
  if (p_lat is null) <> (p_lng is null) or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    perform privado.invalido('localização inválida');
  end if;
  if p_quando is not null then
    if p_quando > now() + interval '2 minutes' or p_quando < now() - interval '24 hours' then
      perform privado.invalido('horário guardado sem internet fora do limite de 24 horas');
    end if;
    v_quando := p_quando;
    v_conf := 'Enviado sem internet';
  end if;

  select * into v_esc from public.escolas where id = privado.escola_atual();
  if p_lat is null then
    v_conf := coalesce(v_conf, 'Sem localização');
  elsif v_esc.latitude is not null then
    v_dist := privado.distancia_m(p_lat, p_lng, v_esc.latitude, v_esc.longitude);
    if v_dist > v_esc.raio_m then v_conf := coalesce(v_conf, 'Fora do raio'); end if;
  end if;
  v_data := (v_quando at time zone 'America/Sao_Paulo')::date;

  if p_evento = 'inicio' then
    insert into public.presencas (oficineiro_id, escola_id, data, inicio, distancia_inicio_m, conferencia)
    values (v_uid, v_esc.id, v_data, v_quando, v_dist, v_conf)
    on conflict (oficineiro_id, data) do nothing
    returning * into v_p;
    if v_p.id is null then perform privado.invalido('a presença deste dia já foi iniciada'); end if;
  else
    select * into v_p from public.presencas
     where oficineiro_id = v_uid and data = v_data and fim is null for update;
    if v_p.id is null then perform privado.invalido('não há presença iniciada hoje para encerrar'); end if;
    if v_quando <= v_p.inicio then perform privado.invalido('encerramento antes do início'); end if;
    v_min := floor(extract(epoch from (v_quando - v_p.inicio)) / 60);
    update public.presencas
       set fim = v_quando,
           distancia_fim_m = v_dist,
           conferencia = coalesce(conferencia, v_conf),
           excedente_min = greatest(0, v_min - 480),
           excedente_status = case when v_min > 480 then 'pendente' else 'dentro' end
     where id = v_p.id
     returning * into v_p;
  end if;

  return jsonb_build_object('id', v_p.id, 'distancia_m', v_dist, 'conferencia', v_p.conferencia,
                            'excedente_min', v_p.excedente_min, 'excedente_status', v_p.excedente_status);
end;
$$;

create or replace function public.justificar_presenca(p_id bigint, p_motivo text, p_justificativa text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_p public.presencas;
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  select * into v_p from public.presencas where id = p_id and oficineiro_id = auth.uid() for update;
  if v_p.id is null then perform privado.negar(); end if;
  if not privado.mes_editavel(v_p.oficineiro_id, v_p.data) then perform privado.invalido('mês fechado: peça a devolução do relatório'); end if;
  if length(trim(coalesce(p_justificativa, ''))) < 10 then perform privado.invalido('justificativa precisa de pelo menos 10 caracteres'); end if;
  if v_p.excedente_status in ('autorizado', 'nao') then perform privado.invalido('o excedente deste dia já foi decidido'); end if;
  update public.presencas
     set motivo = left(trim(p_motivo), 120),
         justificativa = left(trim(p_justificativa), 1000),
         excedente_status = case when excedente_status = 'pendente' then 'aguardando' else excedente_status end
   where id = p_id;
end;
$$;

create or replace function public.decidir_excedente(p_id bigint, p_autorizar boolean)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if privado.papel_atual() is distinct from 'coordenador' or not privado.acesso_ok() then perform privado.negar(); end if;
  update public.presencas
     set excedente_status = case when p_autorizar then 'autorizado' else 'nao' end,
         decidido_por = auth.uid(), decidido_em = now()
   where id = p_id and excedente_status = 'aguardando';
  if not found then perform privado.invalido('não há excedente aguardando decisão neste registro'); end if;
end;
$$;


create or replace function public.conferir_aula(p_id bigint, p_confirmar boolean, p_motivo text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_a public.aulas_registro;
begin
  if privado.papel_atual() is distinct from 'direcao' or not privado.acesso_ok() then perform privado.negar(); end if;
  select * into v_a from public.aulas_registro where id = p_id for update;
  if v_a.id is null or v_a.escola_id is distinct from privado.escola_atual() then perform privado.negar(); end if;
  if v_a.situacao = 'Pendente de registro' then perform privado.invalido('a aula ainda não foi registrada pelo oficineiro'); end if;
  if not p_confirmar and length(trim(coalesce(p_motivo, ''))) < 5 then perform privado.invalido('informe o motivo da contestação'); end if;
  update public.aulas_registro
     set check_direcao = case when p_confirmar then 'ok' else 'contestada' end,
         check_motivo = case when p_confirmar then null else left(trim(p_motivo), 500) end,
         check_por = auth.uid(), check_em = now()
   where id = p_id;
end;
$$;

create or replace function public.fechar_relatorio(p_competencia date)
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare
  v_comp date := date_trunc('month', p_competencia)::date;
  v_id bigint;
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  if v_comp > date_trunc('month', privado.hoje())::date then perform privado.invalido('não é possível fechar um mês futuro'); end if;
  insert into public.relatorios_mensais (oficineiro_id, escola_id, competencia, status)
  values (auth.uid(), privado.escola_atual(), v_comp, 'fechado')
  on conflict (oficineiro_id, competencia) do update
     set status = 'fechado', fechado_em = now(), motivo_devolucao = null,
         direcao_por = null, direcao_em = null, coordenacao_por = null, coordenacao_em = null
   where public.relatorios_mensais.status = 'devolvido'
  returning id into v_id;
  if v_id is null then perform privado.invalido('este mês já está fechado'); end if;
  return v_id;
end;
$$;

create or replace function public.aprovar_relatorio(p_id bigint)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_r public.relatorios_mensais; v_papel public.papel := privado.papel_atual();
begin
  if not privado.acesso_ok() then perform privado.negar(); end if;
  select * into v_r from public.relatorios_mensais where id = p_id for update;
  if v_r.id is null then perform privado.negar(); end if;
  if v_papel = 'direcao' and v_r.escola_id = privado.escola_atual() and v_r.status = 'fechado' then
    update public.relatorios_mensais set status = 'aprovado_direcao', direcao_por = auth.uid(), direcao_em = now() where id = p_id;
  elsif v_papel = 'coordenador' and v_r.status = 'aprovado_direcao' then
    update public.relatorios_mensais set status = 'aprovado_coordenacao', coordenacao_por = auth.uid(), coordenacao_em = now() where id = p_id;
  else
    perform privado.negar('este relatório não está na sua etapa de aprovação');
  end if;
end;
$$;

create or replace function public.devolver_relatorio(p_id bigint, p_motivo text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_r public.relatorios_mensais; v_papel public.papel := privado.papel_atual();
begin
  if not privado.acesso_ok() then perform privado.negar(); end if;
  if length(trim(coalesce(p_motivo, ''))) < 5 then perform privado.invalido('informe o motivo da devolução'); end if;
  select * into v_r from public.relatorios_mensais where id = p_id for update;
  if v_r.id is null then perform privado.negar(); end if;
  if (v_papel = 'direcao' and v_r.escola_id = privado.escola_atual() and v_r.status = 'fechado')
     or (v_papel = 'coordenador' and v_r.status = 'aprovado_direcao') then
    update public.relatorios_mensais set status = 'devolvido', motivo_devolucao = left(trim(p_motivo), 1000) where id = p_id;
  else
    perform privado.negar('este relatório não está na sua etapa de aprovação');
  end if;
end;
$$;


create or replace function public.importar_os(p_os jsonb)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_servico boolean := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '') = 'service_role';
  v_num text := regexp_replace(coalesce(p_os ->> 'numero', ''), '\D', '', 'g');
  v_sec text := upper(coalesce(p_os ->> 'secretaria', ''));
  v_id text;
  v_l jsonb;
  v_cpf text;
  v_hash bytea;
  v_esc smallint;
  v_dup text;
  v_ins int := 0;
  v_dups jsonb := '[]'::jsonb;
  v_inv jsonb := '[]'::jsonb;
begin
  if not v_servico and (privado.papel_atual() is distinct from 'gerente' or not privado.acesso_ok()) then perform privado.negar(); end if;
  if v_num = '' or length(v_num) > 5 then perform privado.invalido('número da OS inválido'); end if;
  if v_sec not in ('SEMED', 'SEMAD', 'SEMSA') then perform privado.invalido('secretaria inválida'); end if;
  if jsonb_typeof(p_os -> 'linhas') <> 'array' or jsonb_array_length(p_os -> 'linhas') = 0 then perform privado.invalido('a OS não tem linhas'); end if;
  if jsonb_array_length(p_os -> 'linhas') > 5000 then perform privado.invalido('OS com mais de 5000 linhas'); end if;

  v_num := lpad(v_num, 3, '0');
  v_id := v_sec || '-' || v_num;
  insert into public.onboarding_os (id, numero, secretaria, arquivo, recebida_em, importada_por)
  values (v_id, v_num, v_sec, left(p_os ->> 'arquivo', 200), coalesce((p_os ->> 'recebida_em')::date, privado.hoje()), auth.uid())
  on conflict (id) do update set arquivo = excluded.arquivo;

  for v_l in select * from jsonb_array_elements(p_os -> 'linhas') loop
    v_cpf := privado.cpf_normalizado(v_l ->> 'cpf');
    if v_cpf is null or length(trim(coalesce(v_l ->> 'nome', ''))) < 3 then
      v_inv := v_inv || to_jsonb(coalesce(v_l ->> 'seq', '?'));
      continue;
    end if;
    v_hash := privado.cpf_hash(v_cpf);
    select os_id into v_dup from public.onboarding_itens where cpf_hash = v_hash limit 1;
    if v_dup is not null then
      v_dups := v_dups || jsonb_build_object('seq', v_l ->> 'seq', 'os', v_dup);
      continue;
    end if;
    select id into v_esc from public.escolas where lower(sigla) = lower(v_l ->> 'escola_sigla');
    insert into public.onboarding_itens (os_id, nome, email, cpf_cifrado, cpf_hash, cpf_mascara, matricula, cargo, tipo,
                                         lotacao_original, escola_id, carteira_id)
    values (v_id, left(regexp_replace(trim(v_l ->> 'nome'), '\s+', ' ', 'g'), 160),
            nullif(lower(trim(v_l ->> 'email')), ''),
            privado.cpf_cifrar(v_cpf), v_hash, privado.cpf_mascara(v_cpf),
            left(trim(v_l ->> 'matricula'), 20), left(trim(v_l ->> 'cargo'), 80), left(trim(v_l ->> 'tipo'), 40),
            left(trim(v_l ->> 'lotacao'), 200), v_esc,
            (select c.id from public.carteiras c where c.id = v_l ->> 'carteira_id'));
    v_ins := v_ins + 1;
  end loop;

  perform auditoria.registrar('IMPORTAR_OS', 'onboarding_os', v_id,
          jsonb_build_object('inseridos', v_ins, 'duplicados', jsonb_array_length(v_dups), 'invalidos', jsonb_array_length(v_inv)));
  return jsonb_build_object('os', v_id, 'inseridos', v_ins, 'duplicados', v_dups, 'invalidos', v_inv);
end;
$$;

create or replace function public.dar_baixa_onboarding(p_id bigint, p_data date, p_forma text, p_obs text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_i public.onboarding_itens; v_papel public.papel := privado.papel_atual();
begin
  if not privado.acesso_ok() or v_papel not in ('gerente', 'analista') then perform privado.negar(); end if;
  select * into v_i from public.onboarding_itens where id = p_id for update;
  if v_i.id is null or (v_papel = 'analista' and v_i.carteira_id is distinct from privado.carteira_atual()) then perform privado.negar(); end if;
  if v_i.status = 'concluido' then perform privado.invalido('este item já teve baixa'); end if;
  if p_data is null or p_data > privado.hoje() then perform privado.invalido('data da baixa inválida'); end if;
  if length(trim(coalesce(p_forma, ''))) < 3 then perform privado.invalido('informe a forma de atendimento'); end if;
  update public.onboarding_itens
     set status = 'concluido', baixa_data = p_data, baixa_forma = left(trim(p_forma), 80),
         baixa_obs = left(trim(p_obs), 1000), baixa_por = auth.uid()
   where id = p_id;
end;
$$;

create or replace function public.reabrir_onboarding(p_id bigint)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not privado.ve_tudo() then perform privado.negar(); end if;
  update public.onboarding_itens set status = 'pendente', baixa_data = null, baixa_forma = null, baixa_obs = null, baixa_por = null
   where id = p_id;
  if not found then perform privado.invalido('item não encontrado'); end if;
end;
$$;

create or replace function public.atribuir_onboarding(p_id bigint, p_carteira text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not privado.ve_tudo() then perform privado.negar(); end if;
  if not exists (select 1 from public.carteiras where id = p_carteira) then perform privado.invalido('carteira inexistente'); end if;
  update public.onboarding_itens set carteira_id = p_carteira where id = p_id;
  if not found then perform privado.invalido('item não encontrado'); end if;
end;
$$;

create or replace function public.revelar_cpf(p_id bigint)
returns text
language plpgsql security definer set search_path = ''
as $$
declare v_c bytea;
begin
  if privado.papel_atual() is distinct from 'gerente' or not privado.acesso_ok() then perform privado.negar(); end if;
  select cpf_cifrado into v_c from public.onboarding_itens where id = p_id;
  if v_c is null then perform privado.invalido('item não encontrado'); end if;
  perform auditoria.registrar('REVELAR_CPF', 'onboarding_itens', p_id::text, null);
  return privado.cpf_decifrar(v_c);
end;
$$;

create or replace function public.auditoria_recente(p_limite integer default 100)
returns setof auditoria.eventos
language plpgsql security definer set search_path = ''
as $$
begin
  if privado.papel_atual() is distinct from 'gerente' or not privado.acesso_ok() then perform privado.negar(); end if;
  return query select * from auditoria.eventos order by em desc limit least(greatest(p_limite, 1), 1000);
end;
$$;

revoke all on function public.registrar_presenca(text, double precision, double precision, timestamptz),
  public.justificar_presenca(bigint, text, text), public.decidir_excedente(bigint, boolean),
  public.conferir_aula(bigint, boolean, text), public.fechar_relatorio(date), public.aprovar_relatorio(bigint),
  public.devolver_relatorio(bigint, text), public.importar_os(jsonb), public.dar_baixa_onboarding(bigint, date, text, text),
  public.reabrir_onboarding(bigint), public.atribuir_onboarding(bigint, text), public.revelar_cpf(bigint),
  public.auditoria_recente(integer)
  from public, anon;
grant execute on function public.registrar_presenca(text, double precision, double precision, timestamptz),
  public.justificar_presenca(bigint, text, text), public.decidir_excedente(bigint, boolean),
  public.conferir_aula(bigint, boolean, text), public.fechar_relatorio(date), public.aprovar_relatorio(bigint),
  public.devolver_relatorio(bigint, text), public.importar_os(jsonb), public.dar_baixa_onboarding(bigint, date, text, text),
  public.reabrir_onboarding(bigint), public.atribuir_onboarding(bigint, text), public.revelar_cpf(bigint),
  public.auditoria_recente(integer)
  to authenticated;
grant execute on function public.importar_os(jsonb) to service_role;

create or replace function auditoria.trigger_linha()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_novo jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) - 'cpf_cifrado' - 'cpf_hash' end;
  v_velho jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) - 'cpf_cifrado' - 'cpf_hash' end;
  v_det jsonb;
begin
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

do $$
declare t text;
begin
  foreach t in array array['carteiras', 'escolas', 'perfis', 'presencas', 'aulas_registro', 'relatorios_mensais',
                           'visitas', 'onboarding_os', 'onboarding_itens'] loop
    execute format('create trigger auditoria after insert or update or delete on public.%I
                    for each row execute function auditoria.trigger_linha()', t);
  end loop;
end $$;

create or replace function auditoria.trigger_carga()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare n bigint;
begin
  if tg_op = 'INSERT' then select count(*) into n from novas; else select count(*) into n from antigas; end if;
  perform auditoria.registrar('CARGA_' || tg_op, tg_table_name, null, jsonb_build_object('linhas', n));
  return null;
end;
$$;
create trigger auditoria_carga_ins after insert on public.jornada_pessoas
  referencing new table as novas for each statement execute function auditoria.trigger_carga();
create trigger auditoria_carga_del after delete on public.jornada_pessoas
  referencing old table as antigas for each statement execute function auditoria.trigger_carga();
