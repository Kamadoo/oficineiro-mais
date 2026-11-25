create or replace function privado.convites_reservar(p_ator uuid, p_ids uuid[], p_reenviar boolean)
returns table (usuario_id uuid, convite_id bigint, resultado text, nome text, email text)
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid;
  v_email text;
  v_nome text;
  v_enviado boolean;
  v_convite bigint;
  v_papel text;
begin
  select p.papel::text into v_papel
    from public.perfis p
   where p.id = p_ator and p.ativo and not p.trocar_senha and p.removido_em is null;
  if v_papel is null or v_papel not in ('administrador', 'gerente', 'coordenador') then perform privado.negar(); end if;
  if p_ids is null or cardinality(p_ids) = 0 then perform privado.invalido('selecione ao menos uma conta'); end if;
  if cardinality(p_ids) > 50 then perform privado.invalido('envie no máximo 50 convites por vez'); end if;
  if v_papel <> 'administrador' and (coalesce(p_reenviar, false) or cardinality(p_ids) > 1) then
    perform privado.negar();
  end if;
  perform pg_advisory_xact_lock(hashtext('fsm_convites_primeiro_acesso'));
  for v_id in select distinct x from unnest(p_ids) as x where x is not null loop
    select p.nome, u.email::text into v_nome, v_email
      from public.perfis p join auth.users u on u.id = p.id
     where p.id = v_id and privado.convite_pendente(p.id);
    if v_papel <> 'administrador' and not exists (
         select 1 from auditoria.eventos a
          where a.acao = 'CADASTRAR_USUARIO' and a.usuario_id = p_ator and a.registro = v_id::text
            and a.em >= now() - interval '1 hour') then
      v_nome := null;
    end if;
    if v_nome is null or v_email is null or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or v_email ~* '@conta\.invalid$' then
      usuario_id := v_id; convite_id := null; resultado := 'indisponivel'; nome := null; email := null;
      return next;
      continue;
    end if;
    if exists (select 1 from privado.convites k
                where k.usuario_id = v_id and k.situacao = 'enviando' and k.criado_em >= now() - interval '15 minutes') then
      usuario_id := v_id; convite_id := null; resultado := 'em_envio'; nome := v_nome; email := null;
      return next;
      continue;
    end if;
    v_enviado := exists (select 1 from privado.convites k where k.usuario_id = v_id and k.situacao = 'enviado');
    if v_papel <> 'administrador' and exists (select 1 from privado.convites k where k.usuario_id = v_id) then
      v_enviado := true;
    end if;
    if v_enviado and (not coalesce(p_reenviar, false) or v_papel <> 'administrador') then
      usuario_id := v_id; convite_id := null; resultado := 'ja_enviado'; nome := v_nome; email := null;
      return next;
      continue;
    end if;
    insert into privado.convites (usuario_id, enviado_por, reenvio)
    values (v_id, p_ator, v_enviado)
    returning id into v_convite;
    usuario_id := v_id; convite_id := v_convite; resultado := 'reservado'; nome := v_nome; email := v_email;
    return next;
  end loop;
end;
$$;

create or replace function privado.convites_concluir(p_ator uuid, p_resultados jsonb)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  r jsonb;
  v_ok boolean;
  v_linha privado.convites%rowtype;
  v_enviados integer := 0;
  v_falhas integer := 0;
  v_papel text;
begin
  select p.papel::text into v_papel from public.perfis p where p.id = p_ator;
  if v_papel is null or v_papel not in ('administrador', 'gerente', 'coordenador') then perform privado.negar(); end if;
  if jsonb_typeof(p_resultados) is distinct from 'array' or jsonb_array_length(p_resultados) > 50 then
    perform privado.invalido('resultados inválidos');
  end if;
  for r in select * from jsonb_array_elements(p_resultados) loop
    if jsonb_typeof(r -> 'convite_id') is distinct from 'number' then continue; end if;
    v_ok := coalesce((r ->> 'ok')::boolean, false);
    update privado.convites k
       set situacao = case when v_ok then 'enviado' else 'falhou' end,
           enviado_em = case when v_ok then now() else null end,
           detalhe = left(nullif(r ->> 'detalhe', ''), 200)
     where k.id = (r ->> 'convite_id')::bigint and k.enviado_por = p_ator and k.situacao = 'enviando'
    returning * into v_linha;
    if not found then continue; end if;
    if v_ok then v_enviados := v_enviados + 1; else v_falhas := v_falhas + 1; end if;
    insert into auditoria.eventos (usuario_id, papel, aal, acao, tabela, registro, detalhes)
    values (p_ator, v_papel, 'aal2', case when v_ok then 'CONVITE_PRIMEIRO_ACESSO' else 'CONVITE_FALHOU' end,
            'perfis', v_linha.usuario_id::text,
            jsonb_build_object('convite', v_linha.id, 'reenvio', v_linha.reenvio));
  end loop;
  return jsonb_build_object('enviados', v_enviados, 'falhas', v_falhas);
end;
$$;

revoke all on function privado.convites_reservar(uuid, uuid[], boolean), privado.convites_concluir(uuid, jsonb)
  from public, anon, authenticated;
grant execute on function privado.convites_reservar(uuid, uuid[], boolean), privado.convites_concluir(uuid, jsonb)
  to service_role;
