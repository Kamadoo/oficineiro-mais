create table if not exists public.jornada_sugestao_descarte (
  id          bigint generated always as identity primary key,
  escola_id   smallint not null references public.escolas (id),
  motivo      text not null check (motivo in ('visita_recente', 'acao_a_distancia', 'escola_fechada', 'outro')),
  detalhe     text check (length(detalhe) <= 500),
  autor_id    uuid references public.perfis (id) on delete set null,
  autor_nome  text not null check (length(autor_nome) between 1 and 120),
  criado_em   timestamptz not null default now()
);
create index if not exists jornada_sugestao_descarte_escola on public.jornada_sugestao_descarte (escola_id, criado_em desc);

alter table public.jornada_sugestao_descarte enable row level security;
revoke all on table public.jornada_sugestao_descarte from public, anon, authenticated;
grant select on table public.jornada_sugestao_descarte to authenticated;

drop policy if exists jornada_sugestao_descarte_ler on public.jornada_sugestao_descarte;
create policy jornada_sugestao_descarte_ler on public.jornada_sugestao_descarte for select to authenticated
  using ((select privado.papel_atual()) in ('gerente', 'coordenador', 'analista') and privado.ve_escola(escola_id));

create or replace function privado.descartar_sugestao_visita(p_escola smallint, p_motivo text, p_detalhe text)
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare
  v_papel public.papel := privado.papel_atual();
  v_id bigint;
  v_detalhe text := nullif(btrim(regexp_replace(coalesce(p_detalhe, ''), '[[:cntrl:]]+', ' ', 'g')), '');
begin
  if not privado.acesso_ok() or v_papel is null or v_papel not in ('gerente', 'analista')
     or not privado.ve_escola(p_escola) then
    perform privado.negar();
  end if;
  if p_motivo is null or p_motivo not in ('visita_recente', 'acao_a_distancia', 'escola_fechada', 'outro') then
    perform privado.invalido('motivo inválido');
  end if;
  if p_motivo = 'outro' and v_detalhe is null then
    perform privado.invalido('descreva o motivo do descarte');
  end if;
  if length(v_detalhe) > 500 then perform privado.invalido('detalhe com mais de 500 caracteres'); end if;
  insert into public.jornada_sugestao_descarte (escola_id, motivo, detalhe, autor_id, autor_nome)
  values (p_escola, p_motivo, v_detalhe, auth.uid(), (select p.nome from public.perfis p where p.id = auth.uid()))
  returning id into v_id;
  perform auditoria.registrar('JORNADA_DESCARTE_SUGESTAO', 'jornada_sugestao_descarte', v_id::text,
                              jsonb_build_object('escola_id', p_escola, 'motivo', p_motivo));
  return v_id;
end;
$$;

create or replace function public.descartar_sugestao_visita(p_escola smallint, p_motivo text, p_detalhe text default null)
returns bigint
language sql security invoker set search_path = ''
as $$ select privado.descartar_sugestao_visita(p_escola, p_motivo, p_detalhe) $$;

revoke all on function privado.descartar_sugestao_visita(smallint, text, text),
                       public.descartar_sugestao_visita(smallint, text, text)
  from public, anon, authenticated;
grant execute on function privado.descartar_sugestao_visita(smallint, text, text),
                          public.descartar_sugestao_visita(smallint, text, text)
  to authenticated;
