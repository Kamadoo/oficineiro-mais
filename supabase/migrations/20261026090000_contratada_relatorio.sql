alter table public.perfis
  add column if not exists contratada_tipo text,
  add column if not exists contratada_cifrado bytea,
  add column if not exists contratada_mascara text;

alter table public.perfis drop constraint if exists perfis_contratada_check;
alter table public.perfis add constraint perfis_contratada_check
  check ((contratada_tipo is null and contratada_cifrado is null and contratada_mascara is null)
      or (contratada_tipo in ('CNPJ', 'CPF') and contratada_cifrado is not null and contratada_mascara is not null));

create or replace function privado.cnpj_normalizado(p_cnpj text)
returns text
language plpgsql immutable set search_path = ''
as $$
declare
  d text := regexp_replace(coalesce(p_cnpj, ''), '\D', '', 'g');
  p1 int[] := array[5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
  p2 int[] := array[6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
  s int; dv int;
begin
  if length(d) <> 14 or d ~ '^(\d)\1{13}$' then return null; end if;
  s := 0;
  for i in 1..12 loop s := s + substr(d, i, 1)::int * p1[i]; end loop;
  dv := case when s % 11 < 2 then 0 else 11 - s % 11 end;
  if dv <> substr(d, 13, 1)::int then return null; end if;
  s := 0;
  for i in 1..13 loop s := s + substr(d, i, 1)::int * p2[i]; end loop;
  dv := case when s % 11 < 2 then 0 else 11 - s % 11 end;
  if dv <> substr(d, 14, 1)::int then return null; end if;
  return d;
end;
$$;

create or replace function privado.contratada_mascara(p_tipo text, p_doc text)
returns text
language sql immutable set search_path = ''
as $$
  select case p_tipo
           when 'CPF' then privado.cpf_mascara(p_doc)
           when 'CNPJ' then '**.***.' || substr(p_doc, 6, 3) || '/' || substr(p_doc, 9, 4) || '-**'
         end;
$$;

create or replace function privado.contratada_formatada(p_tipo text, p_doc text)
returns text
language sql immutable set search_path = ''
as $$
  select case p_tipo
           when 'CPF' then substr(p_doc, 1, 3) || '.' || substr(p_doc, 4, 3) || '.' || substr(p_doc, 7, 3) || '-' || substr(p_doc, 10, 2)
           when 'CNPJ' then substr(p_doc, 1, 2) || '.' || substr(p_doc, 3, 3) || '.' || substr(p_doc, 6, 3) || '/' || substr(p_doc, 9, 4) || '-' || substr(p_doc, 13, 2)
         end;
$$;

revoke all on function privado.cnpj_normalizado(text), privado.contratada_mascara(text, text), privado.contratada_formatada(text, text)
  from public, anon, authenticated;

create or replace function privado.definir_contratada(p_usuario uuid, p_documento text)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  d text := regexp_replace(coalesce(p_documento, ''), '\D', '', 'g');
  v_tipo text;
  v_doc text;
begin
  if not (coalesce(privado.gestor_ok(), false) or privado.eh_admin()) then perform privado.negar(); end if;
  if d = '' then
    update public.perfis set contratada_tipo = null, contratada_cifrado = null, contratada_mascara = null
     where id = p_usuario and papel = 'oficineiro';
    if not found then perform privado.invalido('o CNPJ ou CPF da contratada só vale para contas de oficineiro'); end if;
    return null;
  end if;
  if length(d) = 14 then
    v_tipo := 'CNPJ'; v_doc := privado.cnpj_normalizado(d);
  elsif length(d) = 11 then
    v_tipo := 'CPF'; v_doc := privado.cpf_normalizado(d);
  end if;
  if v_doc is null then perform privado.invalido('informe um CNPJ (14 números) ou CPF (11 números) válido da contratada'); end if;
  update public.perfis
     set contratada_tipo = v_tipo,
         contratada_cifrado = privado.cpf_cifrar(v_doc),
         contratada_mascara = privado.contratada_mascara(v_tipo, v_doc)
   where id = p_usuario and papel = 'oficineiro';
  if not found then perform privado.invalido('o CNPJ ou CPF da contratada só vale para contas de oficineiro'); end if;
  return privado.contratada_mascara(v_tipo, v_doc);
end;
$$;

create or replace function privado.contratadas_gestao()
returns table(id uuid, tipo text, mascara text)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not (coalesce(privado.gestor_ok(), false) or privado.eh_admin()) then perform privado.negar(); end if;
  return query
    select p.id, p.contratada_tipo, p.contratada_mascara
      from public.perfis p
     where p.papel::text = 'oficineiro' and p.contratada_tipo is not null;
end;
$$;

create or replace function privado.minha_contratada()
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare v public.perfis;
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  select * into v from public.perfis where id = auth.uid();
  if v.contratada_tipo is null then return jsonb_build_object('tipo', null, 'documento', null); end if;
  return jsonb_build_object('tipo', v.contratada_tipo,
                            'documento', privado.contratada_formatada(v.contratada_tipo, privado.cpf_decifrar(v.contratada_cifrado)));
end;
$$;

revoke all on function privado.definir_contratada(uuid, text), privado.contratadas_gestao(), privado.minha_contratada() from public, anon;
grant execute on function privado.definir_contratada(uuid, text), privado.contratadas_gestao(), privado.minha_contratada() to authenticated;

create or replace function public.definir_contratada(p_usuario uuid, p_documento text)
returns text
language sql security invoker set search_path = ''
as $$ select privado.definir_contratada(p_usuario, p_documento) $$;

create or replace function public.contratadas_gestao()
returns table(id uuid, tipo text, mascara text)
language sql stable security invoker set search_path = ''
as $$ select * from privado.contratadas_gestao() $$;

create or replace function public.minha_contratada()
returns jsonb
language sql stable security invoker set search_path = ''
as $$ select privado.minha_contratada() $$;

revoke all on function public.definir_contratada(uuid, text), public.contratadas_gestao(), public.minha_contratada() from public, anon;
grant execute on function public.definir_contratada(uuid, text), public.contratadas_gestao(), public.minha_contratada() to authenticated;

create or replace function auditoria.trigger_linha()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_novo jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) - 'cpf_cifrado' - 'cpf_hash' - 'contratada_cifrado' end;
  v_velho jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) - 'cpf_cifrado' - 'cpf_hash' - 'contratada_cifrado' end;
  v_det jsonb;
begin
  if tg_op = 'UPDATE' then
    select jsonb_object_agg(k, jsonb_build_object('de', v_velho -> k, 'para', v_novo -> k)) into v_det
      from jsonb_object_keys(v_novo) k where v_novo -> k is distinct from v_velho -> k;
    if v_det is null then return new; end if;
  else
    v_det := coalesce(v_novo, v_velho);
  end if;
  perform auditoria.registrar(tg_op, tg_table_name, coalesce(v_novo, v_velho) ->> 'id', v_det);
  return coalesce(new, old);
end;
$$;

create or replace function privado.grade_sem_conflito()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if exists (
    select 1
      from public.grade_aulas g
     where g.oficineiro_id = new.oficineiro_id
       and g.escola_id = new.escola_id
       and g.id is distinct from new.id
       and g.ano_letivo = new.ano_letivo
       and g.dia_semana = new.dia_semana
       and g.inicio < new.fim and new.inicio < g.fim
  ) then
    raise exception 'já existe uma atividade sua neste horário' using errcode = '22023';
  end if;
  return new;
end;
$$;
revoke all on function privado.grade_sem_conflito() from public, anon;
