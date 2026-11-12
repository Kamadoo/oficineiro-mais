alter table public.perfis add column if not exists desativado_em timestamptz;
alter table public.perfis add column if not exists removido_em timestamptz;

update public.perfis set desativado_em = now() where not ativo and desativado_em is null;

create or replace function privado.marcar_desativacao()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if new.ativo then
    new.desativado_em := null;
  elsif tg_op = 'INSERT' or old.ativo then
    new.desativado_em := now();
  else
    new.desativado_em := coalesce(new.desativado_em, old.desativado_em, now());
  end if;
  return new;
end;
$$;
revoke all on function privado.marcar_desativacao() from public, anon, authenticated;

drop trigger if exists marcar_desativacao on public.perfis;
create trigger marcar_desativacao
  before insert or update of ativo, desativado_em on public.perfis
  for each row execute function privado.marcar_desativacao();

create or replace function privado.limpar_login(p_id uuid, p_apagar boolean)
returns text
language plpgsql security definer set search_path = ''
as $$
begin
  begin
    if p_apagar then
      delete from auth.users where id = p_id;
    else
      update auth.users
         set email = 'removida.' || replace(p_id::text, '-', '') || '@conta.invalid',
             encrypted_password = extensions.crypt(gen_random_uuid()::text, extensions.gen_salt('bf'))
       where id = p_id;
    end if;
  exception when insufficient_privilege or undefined_table or undefined_column then
    return 'pendente';
  end;
  if not p_apagar then
    begin
      update auth.users
         set raw_user_meta_data = '{}'::jsonb, phone = null, banned_until = now() + interval '100 years'
       where id = p_id;
    exception when insufficient_privilege or undefined_table or undefined_column then
      null;
    end;
    begin
      delete from auth.mfa_factors where user_id = p_id;
    exception when insufficient_privilege or undefined_table or undefined_column then
      null;
    end;
    begin
      delete from auth.identities where user_id = p_id;
    exception when insufficient_privilege or undefined_table or undefined_column then
      null;
    end;
    begin
      delete from auth.sessions where user_id = p_id;
    exception when insufficient_privilege or undefined_table or undefined_column then
      null;
    end;
  end if;
  return 'limpo';
end;
$$;

create or replace function privado.remover_conta(p_id uuid, p_ator uuid, p_motivo text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v public.perfis;
  v_res text;
  v_login text;
begin
  select * into v from public.perfis where id = p_id for update;
  if v.id is null then perform privado.invalido('conta não encontrada'); end if;
  if v.papel = 'administrador' then perform privado.negar('contas de administrador não podem ser apagadas'); end if;
  if p_ator is not null and p_ator = p_id then perform privado.negar('não é possível apagar a própria conta'); end if;
  begin
    delete from public.perfis where id = p_id;
    v_res := 'apagada';
  exception when foreign_key_violation then
    v_res := 'anonimizada';
  end;
  if v_res = 'anonimizada' then
    delete from privado.conta_extras where usuario_id = p_id;
    update public.mudancas_escola set cancelada_em = now()
     where usuario_id = p_id and aplicada_em is null and cancelada_em is null;
    update public.perfis
       set nome = 'Conta removida', usuario = null, telefone = null,
           cpf_cifrado = null, cpf_hash = null, cpf_mascara = null,
           contratada_tipo = null, contratada_cifrado = null, contratada_mascara = null,
           ativo = false, removido_em = coalesce(removido_em, now())
     where id = p_id;
  end if;
  v_login := privado.limpar_login(p_id, v_res = 'apagada');
  perform auditoria.registrar('REMOVER_CONTA', 'perfis', p_id::text,
    jsonb_build_object('papel', v.papel, 'resultado', v_res, 'login', v_login,
                       'por', coalesce(p_ator::text, 'automático'), 'motivo', left(coalesce(p_motivo, ''), 500)));
  return jsonb_build_object('resultado', v_res, 'login', v_login);
end;
$$;

create or replace function privado.remover_contas_desativadas()
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  r record;
  n integer := 0;
begin
  for r in
    select id from public.perfis
     where not ativo and removido_em is null and papel::text <> 'administrador'
       and desativado_em < now() - interval '30 days'
     order by desativado_em
  loop
    begin
      perform privado.remover_conta(r.id, null, 'Conta desativada há mais de 30 dias');
      n := n + 1;
    exception when others then
      raise warning 'não foi possível remover a conta %: %', r.id, sqlerrm;
    end;
  end loop;
  return n;
end;
$$;

revoke all on function privado.limpar_login(uuid, boolean), privado.remover_conta(uuid, uuid, text),
  privado.remover_contas_desativadas() from public, anon, authenticated;
grant execute on function privado.remover_conta(uuid, uuid, text) to service_role;

create or replace function public.remover_conta(p_ator uuid, p_id uuid, p_motivo text)
returns jsonb language sql security invoker set search_path = ''
as $$ select privado.remover_conta(p_id, p_ator, p_motivo) $$;

revoke all on function public.remover_conta(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.remover_conta(uuid, uuid, text) to service_role;

drop function if exists public.contas_gestao();
drop function if exists privado.contas_gestao();

create or replace function privado.contas_gestao()
returns table (id uuid, nome text, usuario text, papel text, escola_id smallint, carteira_id text, ativo boolean,
               primeiro_acesso boolean, criado_em timestamptz, ultimo_acesso timestamptz, telefone text,
               mudanca_escola smallint, mudanca_vale date, mudanca_motivo text, eu boolean, jornada_inicio text,
               trocar_senha boolean, desativado_em timestamptz)
language plpgsql security definer set search_path = ''
as $$
declare
  v_admin boolean := privado.eh_admin();
  v_todos boolean := privado.eh_admin() or privado.papel_atual() = 'gerente';
begin
  if not coalesce(privado.gestor_ok(), false) then perform privado.negar(); end if;
  perform privado.aplicar_mudancas_escola();
  return query
    select p.id, p.nome, p.usuario, p.papel::text, p.escola_id, p.carteira_id, p.ativo,
           (p.usuario is null or p.trocar_senha), p.criado_em, x.acesso_atual, p.telefone,
           m.escola_nova, m.vale_a_partir, m.motivo, p.id = auth.uid(), to_char(p.jornada_inicio, 'HH24:MI'),
           p.trocar_senha, p.desativado_em
      from public.perfis p
      left join privado.conta_extras x on x.usuario_id = p.id
      left join public.mudancas_escola m on m.usuario_id = p.id and m.aplicada_em is null and m.cancelada_em is null
     where p.removido_em is null
       and (v_admin or p.papel::text <> 'administrador')
       and (v_todos or p.papel::text in ('oficineiro', 'direcao') or p.id = auth.uid())
     order by p.nome;
end;
$$;

create or replace function public.contas_gestao()
returns table (id uuid, nome text, usuario text, papel text, escola_id smallint, carteira_id text, ativo boolean,
               primeiro_acesso boolean, criado_em timestamptz, ultimo_acesso timestamptz, telefone text,
               mudanca_escola smallint, mudanca_vale date, mudanca_motivo text, eu boolean, jornada_inicio text,
               trocar_senha boolean, desativado_em timestamptz)
language sql security invoker set search_path = ''
as $$ select * from privado.contas_gestao() $$;

revoke all on function privado.contas_gestao(), public.contas_gestao() from public, anon;
grant execute on function privado.contas_gestao(), public.contas_gestao() to authenticated;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron with schema pg_catalog;
    perform cron.schedule('fsm-remover-contas-desativadas', '17 6 * * *',
                          'select privado.remover_contas_desativadas()');
  else
    raise notice 'pg_cron indisponível: a remoção automática não foi agendada';
  end if;
exception when others then
  raise notice 'não foi possível agendar a remoção automática: %', sqlerrm;
end $$;
