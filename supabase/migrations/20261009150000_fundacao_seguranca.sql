create extension if not exists pgcrypto with schema extensions;

create schema if not exists privado;
create schema if not exists auditoria;
revoke all on schema privado, auditoria from public;
revoke all on schema privado, auditoria from anon, authenticated;
grant usage on schema privado to authenticated;

alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;
alter default privileges revoke execute on functions from public;
revoke create on schema public from public;

do $$
begin
  if not exists (select 1 from vault.secrets where name = 'fsm_cpf_chave') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'base64'), 'fsm_cpf_chave', 'FSM: chave de cifra do CPF');
  end if;
  if not exists (select 1 from vault.secrets where name = 'fsm_cpf_hmac') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'base64'), 'fsm_cpf_hmac', 'FSM: chave HMAC do CPF');
  end if;
end $$;

create or replace function privado.segredo(p_nome text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select decrypted_secret from vault.decrypted_secrets where name = p_nome;
$$;
revoke all on function privado.segredo(text) from public, anon, authenticated;

create or replace function privado.cpf_normalizado(p_cpf text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  d text := lpad(regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g'), 11, '0');
  s int; i int; dv int;
begin
  if length(d) <> 11 or d ~ '^(\d)\1{10}$' then
    return null;
  end if;
  for k in 9..10 loop
    s := 0;
    for i in 1..k loop
      s := s + substr(d, i, 1)::int * (k + 2 - i);
    end loop;
    dv := (s * 10) % 11 % 10;
    if dv <> substr(d, k + 1, 1)::int then
      return null;
    end if;
  end loop;
  return d;
end;
$$;

create or replace function privado.cpf_cifrar(p_cpf text)
returns bytea
language sql
stable
security definer
set search_path = ''
as $$
  select extensions.pgp_sym_encrypt(p_cpf, privado.segredo('fsm_cpf_chave'), 'cipher-algo=aes256');
$$;

create or replace function privado.cpf_hash(p_cpf text)
returns bytea
language sql
stable
security definer
set search_path = ''
as $$
  select extensions.hmac(p_cpf, privado.segredo('fsm_cpf_hmac'), 'sha256');
$$;

create or replace function privado.cpf_decifrar(p_cifrado bytea)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select extensions.pgp_sym_decrypt(p_cifrado, privado.segredo('fsm_cpf_chave'));
$$;

create or replace function privado.cpf_mascara(p_cpf text)
returns text
language sql
immutable
set search_path = ''
as $$
  select '***.' || substr(p_cpf, 4, 3) || '.' || substr(p_cpf, 7, 3) || '-**';
$$;

revoke all on function privado.cpf_normalizado(text), privado.cpf_cifrar(text), privado.cpf_hash(text),
  privado.cpf_decifrar(bytea), privado.cpf_mascara(text) from public, anon, authenticated;

create table auditoria.eventos (
  id         bigint generated always as identity primary key,
  em         timestamptz not null default now(),
  usuario_id uuid,
  papel      text,
  aal        text,
  acao       text not null,
  tabela     text,
  registro   text,
  detalhes   jsonb
);
create index on auditoria.eventos (em desc);
create index on auditoria.eventos (usuario_id, em desc);
revoke all on auditoria.eventos from public, anon, authenticated;

create or replace function auditoria.bloquear_alteracao()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'auditoria é somente inclusão (% bloqueado)', tg_op using errcode = '42501';
end;
$$;
create trigger eventos_imutaveis before update or delete on auditoria.eventos
  for each row execute function auditoria.bloquear_alteracao();
create trigger eventos_sem_truncate before truncate on auditoria.eventos
  for each statement execute function auditoria.bloquear_alteracao();

create or replace function auditoria.registrar(p_acao text, p_tabela text, p_registro text, p_detalhes jsonb default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  c jsonb := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb);
  u uuid := nullif(c ->> 'sub', '')::uuid;
  p text;
begin
  if u is not null then
    select papel::text into p from public.perfis where id = u;
  end if;
  insert into auditoria.eventos (usuario_id, papel, aal, acao, tabela, registro, detalhes)
  values (u, coalesce(p, c ->> 'role', session_user), c ->> 'aal', p_acao, p_tabela, p_registro, p_detalhes);
end;
$$;
revoke all on function auditoria.registrar(text, text, text, jsonb) from public, anon, authenticated;
