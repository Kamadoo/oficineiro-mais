alter table public.perfis add column if not exists cpf_cifrado bytea;
alter table public.perfis add column if not exists cpf_hash bytea;
alter table public.perfis add column if not exists cpf_mascara text;
alter table public.perfis add column if not exists usuario text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'perfis_usuario_formato') then
    alter table public.perfis add constraint perfis_usuario_formato
      check (usuario is null or usuario ~ '^[a-z][a-z0-9._-]{3,29}$');
  end if;
end $$;
create unique index if not exists perfis_usuario_unico on public.perfis (usuario) where usuario is not null;
create unique index if not exists perfis_cpf_unico on public.perfis (cpf_hash) where cpf_hash is not null;

revoke select on public.perfis from authenticated;
grant select (id, nome, papel, escola_id, carteira_id, turno, ativo, criado_em, trocar_senha, usuario, cpf_mascara)
  on public.perfis to authenticated;

create or replace function privado.acesso_ok()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select privado.papel_atual() is not null and privado.mfa_ok();
$$;

create or replace function privado.senha_trocada()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.encrypted_password is distinct from old.encrypted_password then
    update public.perfis set trocar_senha = false
     where id = new.id and trocar_senha and usuario is not null;
  end if;
  return new;
end;
$$;

create or replace function privado.meu_acesso()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'papel', p.papel,
    'nome', p.nome,
    'usuario', p.usuario,
    'escola_id', p.escola_id,
    'carteira_id', p.carteira_id,
    'precisa_mfa', not privado.mfa_ok(),
    'precisa_criar_usuario', p.usuario is null,
    'precisa_trocar_senha', p.trocar_senha,
    'acesso_ok', privado.acesso_ok()
  )
  from public.perfis p
  where p.id = auth.uid() and p.ativo;
$$;

create or replace function privado.definir_usuario(p_usuario text)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  u text := lower(trim(coalesce(p_usuario, '')));
  v_p public.perfis;
begin
  select * into v_p from public.perfis where id = auth.uid() and ativo for update;
  if v_p.id is null or not privado.mfa_ok() then perform privado.negar(); end if;
  if v_p.usuario is not null then perform privado.invalido('o nome de usuário já foi definido'); end if;
  if u !~ '^[a-z][a-z0-9._-]{3,29}$' then
    perform privado.invalido('use de 4 a 30 caracteres: letras minúsculas, números, ponto, hífen ou sublinhado, começando por letra');
  end if;
  if u ~ '^\d' or regexp_replace(u, '\D', '', 'g') ~ '^\d{11}$' then perform privado.invalido('o nome de usuário não pode ser o CPF'); end if;
  if exists (select 1 from public.perfis where usuario = u) then perform privado.invalido('este nome de usuário já está em uso; escolha outro'); end if;
  update public.perfis set usuario = u where id = v_p.id;
  return u;
end;
$$;
revoke all on function privado.definir_usuario(text) from public, anon;
grant execute on function privado.definir_usuario(text) to authenticated;

create or replace function public.definir_usuario(p_usuario text)
returns text language sql security invoker set search_path = ''
as $$ select privado.definir_usuario(p_usuario) $$;
revoke all on function public.definir_usuario(text) from public, anon;
grant execute on function public.definir_usuario(text) to authenticated;


create or replace function public.fsm_conta_por_cpf(p_cpf text)
returns table (user_id uuid, email text, ativo boolean, primeiro_acesso boolean)
language plpgsql stable security definer set search_path = ''
as $$
declare d text := privado.cpf_normalizado(p_cpf);
begin
  if d is null then return; end if;
  return query
    select p.id, u.email::text, p.ativo, (p.usuario is null or p.trocar_senha)
      from public.perfis p join auth.users u on u.id = p.id
     where p.cpf_hash = privado.cpf_hash(d);
end;
$$;

create or replace function public.fsm_conta_por_usuario(p_usuario text)
returns table (user_id uuid, email text, ativo boolean)
language sql stable security definer set search_path = ''
as $$
  select p.id, u.email::text, p.ativo
    from public.perfis p join auth.users u on u.id = p.id
   where p.usuario = lower(trim(p_usuario));
$$;

create or replace function public.fsm_definir_cpf(p_user uuid, p_cpf text)
returns text
language plpgsql security definer set search_path = ''
as $$
declare d text := privado.cpf_normalizado(p_cpf);
begin
  if d is null then raise exception 'CPF inválido' using errcode = '22023'; end if;
  if exists (select 1 from public.perfis where cpf_hash = privado.cpf_hash(d) and id <> p_user) then
    raise exception 'CPF já cadastrado em outra conta' using errcode = '23505';
  end if;
  update public.perfis
     set cpf_cifrado = privado.cpf_cifrar(d), cpf_hash = privado.cpf_hash(d), cpf_mascara = privado.cpf_mascara(d)
   where id = p_user;
  if not found then raise exception 'conta não encontrada' using errcode = '22023'; end if;
  return privado.cpf_mascara(d);
end;
$$;

create table if not exists privado.tentativas (
  chave  text primary key,
  inicio timestamptz not null default now(),
  qtd    integer not null default 0
);
revoke all on privado.tentativas from public, anon, authenticated;
alter table privado.tentativas enable row level security;

create or replace function public.fsm_tentativa(p_chave text, p_max integer, p_janela_s integer)
returns boolean
language plpgsql security definer set search_path = ''
as $$
declare v privado.tentativas;
begin
  delete from privado.tentativas where inicio < now() - interval '1 day';
  insert into privado.tentativas as t (chave, inicio, qtd) values (p_chave, now(), 1)
  on conflict (chave) do update
     set qtd = case when t.inicio < now() - make_interval(secs => p_janela_s) then 1 else t.qtd + 1 end,
         inicio = case when t.inicio < now() - make_interval(secs => p_janela_s) then now() else t.inicio end
  returning * into v;
  return v.qtd <= p_max;
end;
$$;

create or replace function public.fsm_tentativa_zerar(p_chave text)
returns void language sql security definer set search_path = ''
as $$ delete from privado.tentativas where chave = p_chave $$;

do $$
declare f text;
begin
  foreach f in array array['fsm_conta_por_cpf(text)', 'fsm_conta_por_usuario(text)', 'fsm_definir_cpf(uuid, text)',
                           'fsm_tentativa(text, integer, integer)', 'fsm_tentativa_zerar(text)'] loop
    execute 'revoke all on function public.' || f || ' from public, anon, authenticated';
    execute 'grant execute on function public.' || f || ' to service_role';
  end loop;
end $$;
