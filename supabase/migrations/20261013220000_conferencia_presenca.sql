alter table public.presencas
  add column if not exists conferencia_status text not null default 'pendente' check (conferencia_status in ('pendente', 'conferida', 'nao_conferida')),
  add column if not exists conferencia_obs    text check (length(conferencia_obs) <= 500),
  add column if not exists conferido_por      uuid references public.perfis (id),
  add column if not exists conferido_em       timestamptz,
  add column if not exists excedente_obs      text check (length(excedente_obs) <= 500);

create or replace function privado.conferir_presenca(p_id bigint, p_conferir boolean, p_comentario text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_p public.presencas;
begin
  if privado.papel_atual() is distinct from 'coordenador' or not privado.acesso_ok() then perform privado.negar(); end if;
  select * into v_p from public.presencas where id = p_id for update;
  if v_p.id is null then perform privado.invalido('presença não encontrada'); end if;
  if v_p.conferencia is null and not (v_p.fim is null and v_p.data < privado.hoje()) then
    perform privado.invalido('esta presença não precisa de conferência');
  end if;
  if v_p.conferencia_status <> 'pendente' then perform privado.invalido('esta presença já foi conferida'); end if;
  if not coalesce(p_conferir, false) and length(trim(coalesce(p_comentario, ''))) < 5 then
    perform privado.invalido('explique por que a presença não foi conferida');
  end if;
  update public.presencas
     set conferencia_status = case when p_conferir then 'conferida' else 'nao_conferida' end,
         conferencia_obs = nullif(left(trim(coalesce(p_comentario, '')), 500), ''),
         conferido_por = auth.uid(),
         conferido_em = now()
   where id = p_id;
end;
$$;

create or replace function privado.decidir_excedente(p_id bigint, p_autorizar boolean, p_comentario text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if privado.papel_atual() is distinct from 'coordenador' or not privado.acesso_ok() then perform privado.negar(); end if;
  if not coalesce(p_autorizar, false) and length(trim(coalesce(p_comentario, ''))) < 5 then
    perform privado.invalido('explique por que o excedente não foi autorizado');
  end if;
  update public.presencas
     set excedente_status = case when p_autorizar then 'autorizado' else 'nao' end,
         excedente_obs = nullif(left(trim(coalesce(p_comentario, '')), 500), ''),
         decidido_por = auth.uid(), decidido_em = now()
   where id = p_id and excedente_status = 'aguardando';
  if not found then perform privado.invalido('não há excedente aguardando decisão neste registro'); end if;
end;
$$;

create or replace function public.conferir_presenca(p_id bigint, p_conferir boolean, p_comentario text default null)
returns void language sql security invoker set search_path = ''
as $$ select privado.conferir_presenca(p_id, p_conferir, p_comentario) $$;

create or replace function public.decidir_excedente(p_id bigint, p_autorizar boolean, p_comentario text)
returns void language sql security invoker set search_path = ''
as $$ select privado.decidir_excedente(p_id, p_autorizar, p_comentario) $$;

revoke all on function privado.conferir_presenca(bigint, boolean, text), privado.decidir_excedente(bigint, boolean, text),
  public.conferir_presenca(bigint, boolean, text), public.decidir_excedente(bigint, boolean, text) from public, anon;
grant execute on function privado.conferir_presenca(bigint, boolean, text), privado.decidir_excedente(bigint, boolean, text),
  public.conferir_presenca(bigint, boolean, text), public.decidir_excedente(bigint, boolean, text) to authenticated;
