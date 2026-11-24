create table if not exists privado.convites (
  id          bigint generated always as identity primary key,
  usuario_id  uuid not null references public.perfis (id) on delete cascade,
  enviado_por uuid references public.perfis (id) on delete set null,
  criado_em   timestamptz not null default now(),
  enviado_em  timestamptz,
  situacao    text not null default 'enviando' check (situacao in ('enviando', 'enviado', 'falhou')),
  reenvio     boolean not null default false,
  detalhe     text check (detalhe is null or length(detalhe) <= 200)
);

create index if not exists convites_usuario_idx on privado.convites (usuario_id, criado_em desc);
alter table privado.convites enable row level security;
revoke all on table privado.convites from public, anon, authenticated;

create or replace function privado.convite_pendente(p_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.perfis p
                  where p.id = p_id and p.removido_em is null and p.ativo
                    and p.papel::text <> 'administrador' and (p.usuario is null or p.trocar_senha));
$$;

create or replace function privado.convites_pendentes()
returns table (id uuid, nome text, email text, papel text, escola_id smallint, escola text, carteira_id text,
               criado_em timestamptz, envios integer, ultimo_envio timestamptz, situacao text, ultimo_por text,
               ultima_tentativa timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not coalesce(privado.eh_admin(), false) then perform privado.negar(); end if;
  return query
    select p.id, p.nome, u.email::text, p.papel::text, p.escola_id, e.nome, coalesce(p.carteira_id, e.carteira_id),
           p.criado_em, coalesce(c.n, 0)::integer, c.ultimo,
           case
             when l.situacao is null then 'nunca'
             when l.situacao = 'enviando' and l.criado_em < now() - interval '15 minutes' then 'falhou'
             else l.situacao
           end,
           a.nome, coalesce(l.enviado_em, l.criado_em)
      from public.perfis p
      join auth.users u on u.id = p.id
      left join public.escolas e on e.id = p.escola_id
      left join lateral (
        select count(*) as n, max(k.enviado_em) as ultimo
          from privado.convites k
         where k.usuario_id = p.id and k.situacao = 'enviado') c on true
      left join lateral (
        select k.situacao, k.criado_em, k.enviado_em, k.enviado_por
          from privado.convites k
         where k.usuario_id = p.id
         order by k.criado_em desc, k.id desc
         limit 1) l on true
      left join public.perfis a on a.id = l.enviado_por
     where p.removido_em is null and p.ativo and p.papel::text <> 'administrador'
       and (p.usuario is null or p.trocar_senha)
     order by p.nome;
end;
$$;

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
begin
  if not exists (select 1 from public.perfis p
                  where p.id = p_ator and p.ativo and not p.trocar_senha and p.removido_em is null
                    and p.papel::text = 'administrador') then
    perform privado.negar();
  end if;
  if p_ids is null or cardinality(p_ids) = 0 then perform privado.invalido('selecione ao menos uma conta'); end if;
  if cardinality(p_ids) > 50 then perform privado.invalido('envie no máximo 50 convites por vez'); end if;
  perform pg_advisory_xact_lock(hashtext('fsm_convites_primeiro_acesso'));
  for v_id in select distinct x from unnest(p_ids) as x where x is not null loop
    select p.nome, u.email::text into v_nome, v_email
      from public.perfis p join auth.users u on u.id = p.id
     where p.id = v_id and privado.convite_pendente(p.id);
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
    if v_enviado and not coalesce(p_reenviar, false) then
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
begin
  if not exists (select 1 from public.perfis p where p.id = p_ator and p.papel::text = 'administrador') then
    perform privado.negar();
  end if;
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
    values (p_ator, 'administrador', 'aal2', case when v_ok then 'CONVITE_PRIMEIRO_ACESSO' else 'CONVITE_FALHOU' end,
            'perfis', v_linha.usuario_id::text,
            jsonb_build_object('convite', v_linha.id, 'reenvio', v_linha.reenvio));
  end loop;
  return jsonb_build_object('enviados', v_enviados, 'falhas', v_falhas);
end;
$$;

create or replace function public.convites_pendentes()
returns table (id uuid, nome text, email text, papel text, escola_id smallint, escola text, carteira_id text,
               criado_em timestamptz, envios integer, ultimo_envio timestamptz, situacao text, ultimo_por text,
               ultima_tentativa timestamptz)
language sql stable security invoker set search_path = ''
as $$ select * from privado.convites_pendentes() $$;

create or replace function public.convites_reservar(p_ator uuid, p_ids uuid[], p_reenviar boolean)
returns table (usuario_id uuid, convite_id bigint, resultado text, nome text, email text)
language sql security invoker set search_path = ''
as $$ select * from privado.convites_reservar(p_ator, p_ids, p_reenviar) $$;

create or replace function public.convites_concluir(p_ator uuid, p_resultados jsonb)
returns jsonb
language sql security invoker set search_path = ''
as $$ select privado.convites_concluir(p_ator, p_resultados) $$;

revoke all on function privado.convite_pendente(uuid) from public, anon, authenticated;
revoke all on function privado.convites_pendentes(), public.convites_pendentes() from public, anon;
grant execute on function privado.convites_pendentes(), public.convites_pendentes() to authenticated;
revoke all on function privado.convites_reservar(uuid, uuid[], boolean), public.convites_reservar(uuid, uuid[], boolean),
  privado.convites_concluir(uuid, jsonb), public.convites_concluir(uuid, jsonb) from public, anon, authenticated;
grant execute on function privado.convite_pendente(uuid), privado.convites_reservar(uuid, uuid[], boolean),
  public.convites_reservar(uuid, uuid[], boolean), privado.convites_concluir(uuid, jsonb),
  public.convites_concluir(uuid, jsonb) to service_role;
