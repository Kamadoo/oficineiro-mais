create table if not exists public.erros_navegador (
  id bigint generated always as identity primary key,
  em timestamptz not null default now(),
  usuario_id uuid references public.perfis (id) on delete set null,
  papel text,
  pagina text not null,
  mensagem text not null,
  origem text,
  linha integer,
  coluna integer,
  navegador text,
  versao text
);
create index if not exists erros_navegador_em on public.erros_navegador (em desc);
create index if not exists erros_navegador_usuario on public.erros_navegador (usuario_id, em desc);
alter table public.erros_navegador enable row level security;
revoke all on table public.erros_navegador from public, anon, authenticated;

create or replace function privado.registrar_erro_navegador(
  p_mensagem text, p_pagina text, p_origem text, p_linha integer, p_coluna integer, p_navegador text, p_versao text
)
returns boolean
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_mensagem text := left(regexp_replace(coalesce(p_mensagem, ''), '[[:cntrl:]]+', ' ', 'g'), 500);
  v_pagina text := left(regexp_replace(coalesce(p_pagina, ''), '[[:cntrl:]]+', ' ', 'g'), 200);
begin
  if v_uid is null or not exists (select 1 from public.perfis where id = v_uid and ativo) then
    perform privado.negar();
  end if;
  if btrim(v_mensagem) = '' then
    return false;
  end if;
  if (select count(*) from public.erros_navegador where usuario_id = v_uid and em > now() - interval '1 hour') >= 30 then
    return false;
  end if;
  if exists (select 1 from public.erros_navegador
              where usuario_id = v_uid and mensagem = v_mensagem and pagina = v_pagina
                and em > now() - interval '10 minutes') then
    return false;
  end if;
  insert into public.erros_navegador (usuario_id, papel, pagina, mensagem, origem, linha, coluna, navegador, versao)
  values (v_uid, (select papel::text from public.perfis where id = v_uid), v_pagina, v_mensagem,
          left(regexp_replace(coalesce(p_origem, ''), '[[:cntrl:]]+', ' ', 'g'), 300),
          case when p_linha between 0 and 10000000 then p_linha end,
          case when p_coluna between 0 and 10000000 then p_coluna end,
          left(regexp_replace(coalesce(p_navegador, ''), '[[:cntrl:]]+', ' ', 'g'), 200),
          left(regexp_replace(coalesce(p_versao, ''), '[[:cntrl:]]+', ' ', 'g'), 20));
  return true;
end;
$$;

create or replace function public.registrar_erro_navegador(
  p_mensagem text, p_pagina text, p_origem text, p_linha integer, p_coluna integer, p_navegador text, p_versao text
)
returns boolean
language sql security invoker set search_path = ''
as $$ select privado.registrar_erro_navegador(p_mensagem, p_pagina, p_origem, p_linha, p_coluna, p_navegador, p_versao) $$;

create or replace function privado.admin_erros_navegador(p_limite integer default 200)
returns table (id bigint, em timestamptz, usuario_id uuid, nome text, papel text, pagina text, mensagem text,
               origem text, linha integer, coluna integer, navegador text, versao text)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not privado.eh_admin() then perform privado.negar(); end if;
  return query
    select e.id, e.em, e.usuario_id, p.nome, e.papel, e.pagina, e.mensagem, e.origem, e.linha, e.coluna, e.navegador, e.versao
      from public.erros_navegador e
      left join public.perfis p on p.id = e.usuario_id
     order by e.em desc, e.id desc
     limit least(greatest(coalesce(p_limite, 200), 1), 1000);
end;
$$;

create or replace function public.admin_erros_navegador(p_limite integer default 200)
returns table (id bigint, em timestamptz, usuario_id uuid, nome text, papel text, pagina text, mensagem text,
               origem text, linha integer, coluna integer, navegador text, versao text)
language sql stable security invoker set search_path = ''
as $$ select * from privado.admin_erros_navegador(p_limite) $$;

create or replace function privado.limpar_erros_navegador()
returns integer
language plpgsql security definer set search_path = ''
as $$
declare v integer;
begin
  delete from public.erros_navegador where em < now() - interval '90 days';
  get diagnostics v = row_count;
  return v;
end;
$$;

revoke all on function privado.registrar_erro_navegador(text, text, text, integer, integer, text, text),
                       public.registrar_erro_navegador(text, text, text, integer, integer, text, text),
                       privado.admin_erros_navegador(integer), public.admin_erros_navegador(integer),
                       privado.limpar_erros_navegador()
  from public, anon, authenticated;
grant execute on function privado.registrar_erro_navegador(text, text, text, integer, integer, text, text),
                          public.registrar_erro_navegador(text, text, text, integer, integer, text, text),
                          privado.admin_erros_navegador(integer), public.admin_erros_navegador(integer)
  to authenticated;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron with schema pg_catalog;
    perform cron.schedule('fsm-limpar-erros-navegador', '41 6 * * *', 'select privado.limpar_erros_navegador()');
  else
    raise notice 'pg_cron indisponível: a limpeza dos erros do navegador não foi agendada';
  end if;
exception when others then
  raise notice 'não foi possível agendar a limpeza dos erros do navegador: %', sqlerrm;
end $$;
