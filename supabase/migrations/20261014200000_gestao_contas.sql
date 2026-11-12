alter table public.perfis add column if not exists telefone text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'perfis_telefone_formato') then
    alter table public.perfis add constraint perfis_telefone_formato check (telefone is null or telefone ~ '^[0-9]{10,11}$');
  end if;
end $$;

create table if not exists public.mudancas_escola (
  id              bigint generated always as identity primary key,
  usuario_id      uuid not null references public.perfis (id) on delete cascade,
  escola_anterior smallint not null references public.escolas (id),
  escola_nova     smallint not null references public.escolas (id),
  vale_a_partir   date not null,
  motivo          text not null check (motivo in ('Remanejamento do núcleo', 'Solicitação da SEMED', 'Ampliação de atendimento', 'Outro')),
  criado_por      uuid not null references public.perfis (id),
  criado_em       timestamptz not null default now(),
  aplicada_em     timestamptz,
  cancelada_em    timestamptz,
  check (escola_nova <> escola_anterior)
);
create unique index if not exists mudancas_escola_uma_pendente on public.mudancas_escola (usuario_id)
  where aplicada_em is null and cancelada_em is null;
alter table public.mudancas_escola enable row level security;
revoke all on public.mudancas_escola from anon, authenticated;
grant select on public.mudancas_escola to authenticated;

drop policy if exists mudancas_ler on public.mudancas_escola;
create policy mudancas_ler on public.mudancas_escola for select to authenticated
  using ((select privado.acesso_ok())
         and ((select privado.papel_atual()) in ('gerente', 'coordenador') or usuario_id = (select auth.uid())));

drop trigger if exists auditoria on public.mudancas_escola;
create trigger auditoria after insert or update or delete on public.mudancas_escola
  for each row execute function auditoria.trigger_linha();

create or replace function privado.escola_atual()
returns smallint
language sql stable security definer set search_path = ''
as $$
  select coalesce(
           (select m.escola_nova from public.mudancas_escola m
             where m.usuario_id = p.id and m.aplicada_em is null and m.cancelada_em is null and m.vale_a_partir <= privado.hoje()
             order by m.vale_a_partir desc, m.id desc limit 1),
           p.escola_id)
    from public.perfis p where p.id = auth.uid() and p.ativo;
$$;

create or replace function privado.aplicar_mudancas_escola()
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  m record;
  n integer := 0;
begin
  for m in
    select x.id, x.usuario_id, x.escola_nova from public.mudancas_escola x
     where x.aplicada_em is null and x.cancelada_em is null and x.vale_a_partir <= privado.hoje()
     order by x.id
     for update
  loop
    update public.perfis set escola_id = m.escola_nova where id = m.usuario_id and papel = 'oficineiro';
    update public.mudancas_escola set aplicada_em = now() where id = m.id;
    n := n + 1;
  end loop;
  return n;
end;
$$;
revoke all on function privado.escola_atual() from public, anon;
revoke all on function privado.aplicar_mudancas_escola() from public, anon, authenticated;
grant execute on function privado.escola_atual() to authenticated;

create or replace function privado.gestor_ok()
returns boolean
language sql stable security definer set search_path = ''
as $$ select privado.papel_atual() in ('gerente', 'coordenador') and privado.acesso_ok() $$;
revoke all on function privado.gestor_ok() from public, anon;
grant execute on function privado.gestor_ok() to authenticated;

drop function if exists public.contas_gestao();
drop function if exists privado.contas_gestao();
create or replace function privado.contas_gestao()
returns table (id uuid, nome text, usuario text, papel text, escola_id smallint, carteira_id text, ativo boolean,
               primeiro_acesso boolean, criado_em timestamptz, ultimo_acesso timestamptz, telefone text,
               mudanca_escola smallint, mudanca_vale date, mudanca_motivo text, eu boolean)
language plpgsql security definer set search_path = ''
as $$
begin
  if not coalesce(privado.gestor_ok(), false) then perform privado.negar(); end if;
  perform privado.aplicar_mudancas_escola();
  return query
    select p.id, p.nome, p.usuario, p.papel::text, p.escola_id, p.carteira_id, p.ativo,
           (p.usuario is null or p.trocar_senha), p.criado_em, x.acesso_atual, p.telefone,
           m.escola_nova, m.vale_a_partir, m.motivo, p.id = auth.uid()
      from public.perfis p
      left join privado.conta_extras x on x.usuario_id = p.id
      left join public.mudancas_escola m on m.usuario_id = p.id and m.aplicada_em is null and m.cancelada_em is null
     order by p.nome;
end;
$$;

create or replace function privado.alterar_escola(p_usuario uuid, p_escola smallint, p_vale date, p_motivo text)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_p public.perfis;
  v_hoje date := privado.hoje();
begin
  if not coalesce(privado.gestor_ok(), false) then perform privado.negar(); end if;
  if p_usuario is null or p_usuario = auth.uid() then perform privado.invalido('não é possível alterar a própria conta'); end if;
  perform privado.aplicar_mudancas_escola();
  select * into v_p from public.perfis where id = p_usuario for update;
  if v_p.id is null or v_p.papel <> 'oficineiro' or not v_p.ativo then perform privado.invalido('somente contas ativas de oficineiro mudam de escola'); end if;
  if not exists (select 1 from public.escolas where id = p_escola and ativa) then perform privado.invalido('escola não encontrada'); end if;
  if p_escola = v_p.escola_id then perform privado.invalido('o oficineiro já atua nesta escola'); end if;
  if p_motivo is null or p_motivo not in ('Remanejamento do núcleo', 'Solicitação da SEMED', 'Ampliação de atendimento', 'Outro') then
    perform privado.invalido('escolha o motivo da alteração');
  end if;
  if p_vale is null or p_vale < v_hoje or p_vale > v_hoje + 180 then perform privado.invalido('a data precisa ser de hoje até 6 meses à frente'); end if;
  update public.mudancas_escola set cancelada_em = now()
   where usuario_id = p_usuario and aplicada_em is null and cancelada_em is null;
  insert into public.mudancas_escola (usuario_id, escola_anterior, escola_nova, vale_a_partir, motivo, criado_por)
  values (p_usuario, v_p.escola_id, p_escola, p_vale, p_motivo, auth.uid());
  if p_vale <= v_hoje then
    perform privado.aplicar_mudancas_escola();
    return 'aplicada';
  end if;
  return 'agendada';
end;
$$;

create or replace function privado.cancelar_mudanca_escola(p_usuario uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not coalesce(privado.gestor_ok(), false) then perform privado.negar(); end if;
  if p_usuario is null or p_usuario = auth.uid() then perform privado.invalido('não é possível alterar a própria conta'); end if;
  update public.mudancas_escola set cancelada_em = now()
   where usuario_id = p_usuario and aplicada_em is null and cancelada_em is null and vale_a_partir > privado.hoje();
  if not found then perform privado.invalido('não há mudança de escola agendada para esta conta'); end if;
end;
$$;

create or replace function privado.minha_mudanca_escola()
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare v jsonb;
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  select jsonb_build_object('escola', e.nome, 'vale_a_partir', m.vale_a_partir, 'ja_vale', m.vale_a_partir <= privado.hoje())
    into v
    from public.mudancas_escola m join public.escolas e on e.id = m.escola_nova
   where m.usuario_id = auth.uid() and m.cancelada_em is null and m.vale_a_partir >= privado.hoje() - 7
   order by m.id desc limit 1;
  return v;
end;
$$;

create or replace function public.contas_gestao()
returns table (id uuid, nome text, usuario text, papel text, escola_id smallint, carteira_id text, ativo boolean,
               primeiro_acesso boolean, criado_em timestamptz, ultimo_acesso timestamptz, telefone text,
               mudanca_escola smallint, mudanca_vale date, mudanca_motivo text, eu boolean)
language sql security invoker set search_path = ''
as $$ select * from privado.contas_gestao() $$;

create or replace function public.alterar_escola(p_usuario uuid, p_escola smallint, p_vale date, p_motivo text)
returns text language sql security invoker set search_path = ''
as $$ select privado.alterar_escola(p_usuario, p_escola, p_vale, p_motivo) $$;

create or replace function public.cancelar_mudanca_escola(p_usuario uuid)
returns void language sql security invoker set search_path = ''
as $$ select privado.cancelar_mudanca_escola(p_usuario) $$;

create or replace function public.minha_mudanca_escola()
returns jsonb language sql security invoker set search_path = ''
as $$ select privado.minha_mudanca_escola() $$;

revoke all on function privado.contas_gestao(), privado.alterar_escola(uuid, smallint, date, text), privado.cancelar_mudanca_escola(uuid),
                       privado.minha_mudanca_escola(), public.contas_gestao(), public.alterar_escola(uuid, smallint, date, text),
                       public.cancelar_mudanca_escola(uuid), public.minha_mudanca_escola() from public, anon;
grant execute on function privado.contas_gestao(), privado.alterar_escola(uuid, smallint, date, text), privado.cancelar_mudanca_escola(uuid),
                          privado.minha_mudanca_escola(), public.contas_gestao(), public.alterar_escola(uuid, smallint, date, text),
                          public.cancelar_mudanca_escola(uuid), public.minha_mudanca_escola() to authenticated;

create or replace function public.fsm_registrar_login(p_user uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  perform privado.aplicar_mudancas_escola();
  insert into privado.conta_extras as x (usuario_id, acesso_atual)
  select p.id, now() from public.perfis p where p.id = p_user
  on conflict (usuario_id) do update set acesso_anterior = x.acesso_atual, acesso_atual = now();
end;
$$;
revoke all on function public.fsm_registrar_login(uuid) from public, anon, authenticated;
grant execute on function public.fsm_registrar_login(uuid) to service_role;
