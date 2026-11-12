create table if not exists privado.conta_extras (
  usuario_id      uuid primary key references public.perfis (id) on delete cascade,
  preferencias    jsonb not null default '{}'::jsonb check (jsonb_typeof(preferencias) = 'object' and length(preferencias::text) <= 300),
  acesso_atual    timestamptz,
  acesso_anterior timestamptz
);
revoke all on privado.conta_extras from public, anon, authenticated;
alter table privado.conta_extras enable row level security;

create or replace function privado.minha_conta()
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare v jsonb;
begin
  if not privado.acesso_ok() then perform privado.negar(); end if;
  select jsonb_build_object(
           'nome', p.nome,
           'usuario', p.usuario,
           'papel', p.papel,
           'escola', case when e.id is null then null else jsonb_build_object('sigla', e.sigla, 'nome', e.nome) end,
           'carteira', case when c.id is null then null else jsonb_build_object('id', c.id, 'rotulo', c.rotulo) end,
           'acesso_anterior', x.acesso_anterior)
    into v
    from public.perfis p
    left join public.escolas e on e.id = p.escola_id
    left join public.carteiras c on c.id = p.carteira_id
    left join privado.conta_extras x on x.usuario_id = p.id
   where p.id = auth.uid() and p.ativo;
  if v is null then perform privado.negar(); end if;
  return v;
end;
$$;

create or replace function privado.minhas_preferencias()
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not privado.acesso_ok() then perform privado.negar(); end if;
  return coalesce((select preferencias from privado.conta_extras where usuario_id = auth.uid()), '{}'::jsonb);
end;
$$;

create or replace function privado.salvar_preferencias(p_preferencias jsonb)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_ok jsonb := '{"tema": ["claro", "escuro", "auto"], "texto": ["normal", "grande", "maior"], "animacoes": ["sim", "reduzir"]}'::jsonb;
  k text;
begin
  if not privado.acesso_ok() then perform privado.negar(); end if;
  if p_preferencias is null or jsonb_typeof(p_preferencias) <> 'object' then perform privado.invalido('preferências inválidas'); end if;
  for k in select jsonb_object_keys(p_preferencias) loop
    if not v_ok ? k or jsonb_typeof(p_preferencias -> k) <> 'string' or not (v_ok -> k) ? (p_preferencias ->> k) then
      perform privado.invalido('preferência inválida');
    end if;
  end loop;
  insert into privado.conta_extras as x (usuario_id, preferencias) values (auth.uid(), p_preferencias)
  on conflict (usuario_id) do update set preferencias = x.preferencias || excluded.preferencias;
  return (select preferencias from privado.conta_extras where usuario_id = auth.uid());
end;
$$;

create or replace function public.minha_conta()
returns jsonb language sql security invoker set search_path = ''
as $$ select privado.minha_conta() $$;

create or replace function public.minhas_preferencias()
returns jsonb language sql security invoker set search_path = ''
as $$ select privado.minhas_preferencias() $$;

create or replace function public.salvar_preferencias(p_preferencias jsonb)
returns jsonb language sql security invoker set search_path = ''
as $$ select privado.salvar_preferencias(p_preferencias) $$;

revoke all on function privado.minha_conta(), privado.minhas_preferencias(), privado.salvar_preferencias(jsonb),
                       public.minha_conta(), public.minhas_preferencias(), public.salvar_preferencias(jsonb) from public, anon;
grant execute on function privado.minha_conta(), privado.minhas_preferencias(), privado.salvar_preferencias(jsonb),
                          public.minha_conta(), public.minhas_preferencias(), public.salvar_preferencias(jsonb) to authenticated;

create or replace function public.fsm_registrar_login(p_user uuid)
returns void
language sql security definer set search_path = ''
as $$
  insert into privado.conta_extras as x (usuario_id, acesso_atual)
  select p.id, now() from public.perfis p where p.id = p_user
  on conflict (usuario_id) do update set acesso_anterior = x.acesso_atual, acesso_atual = now();
$$;
revoke all on function public.fsm_registrar_login(uuid) from public, anon, authenticated;
grant execute on function public.fsm_registrar_login(uuid) to service_role;
