alter table public.onboarding_itens alter column cpf_cifrado drop not null;

create or replace function privado.importar_os(p_os jsonb)
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
  v_aluno boolean;
  v_chave text;
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
    v_aluno := (coalesce(v_l ->> 'cargo', '') || ' ' || coalesce(v_l ->> 'tipo', '')) ~* '\m(alun[oa]s?|estudantes?)\M';
    if (v_cpf is null and not v_aluno) or length(trim(coalesce(v_l ->> 'nome', ''))) < 3 then
      v_inv := v_inv || to_jsonb(coalesce(v_l ->> 'seq', '?'));
      continue;
    end if;
    if v_cpf is not null then
      v_hash := privado.cpf_hash(v_cpf);
    else
      v_chave := coalesce(nullif(lower(trim(v_l ->> 'email')), ''), nullif(trim(v_l ->> 'matricula'), ''),
                          lower(regexp_replace(trim(v_l ->> 'nome'), '\s+', ' ', 'g')) || '|' || lower(trim(coalesce(v_l ->> 'lotacao', ''))));
      v_hash := privado.cpf_hash('aluno|' || v_chave);
    end if;
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
            case when v_cpf is null then null else privado.cpf_cifrar(v_cpf) end, v_hash,
            case when v_cpf is null then 'sem CPF' else privado.cpf_mascara(v_cpf) end,
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

revoke all on function privado.importar_os(jsonb) from public, anon;
grant execute on function privado.importar_os(jsonb) to authenticated, service_role;
