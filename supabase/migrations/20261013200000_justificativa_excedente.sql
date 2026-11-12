alter table public.presencas
  add column if not exists motivo_excedente        text check (length(motivo_excedente) <= 120),
  add column if not exists justificativa_excedente text check (length(justificativa_excedente) <= 1000);

create or replace function privado.justificar_presenca(p_id bigint, p_motivo text, p_justificativa text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_p public.presencas;
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  select * into v_p from public.presencas where id = p_id and oficineiro_id = auth.uid() for update;
  if v_p.id is null then perform privado.negar(); end if;
  if not privado.mes_editavel(v_p.oficineiro_id, v_p.data) then perform privado.invalido('mês fechado: peça a devolução do relatório'); end if;
  if length(trim(coalesce(p_justificativa, ''))) < 10 then perform privado.invalido('justificativa precisa de pelo menos 10 caracteres'); end if;
  update public.presencas
     set motivo = left(trim(p_motivo), 120),
         justificativa = left(trim(p_justificativa), 1000)
   where id = p_id;
end;
$$;

create or replace function privado.justificar_excedente(p_id bigint, p_motivo text, p_justificativa text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_p public.presencas;
begin
  if privado.papel_atual() is distinct from 'oficineiro' or not privado.acesso_ok() then perform privado.negar(); end if;
  select * into v_p from public.presencas where id = p_id and oficineiro_id = auth.uid() for update;
  if v_p.id is null then perform privado.negar(); end if;
  if not privado.mes_editavel(v_p.oficineiro_id, v_p.data) then perform privado.invalido('mês fechado: peça a devolução do relatório'); end if;
  if v_p.excedente_status not in ('pendente', 'aguardando') then perform privado.invalido('não há horas acima de 8h para justificar neste dia'); end if;
  if length(trim(coalesce(p_motivo, ''))) = 0 then perform privado.invalido('escolha o motivo'); end if;
  if length(trim(coalesce(p_justificativa, ''))) < 10 then perform privado.invalido('justificativa precisa de pelo menos 10 caracteres'); end if;
  update public.presencas
     set motivo_excedente = left(trim(p_motivo), 120),
         justificativa_excedente = left(trim(p_justificativa), 1000),
         excedente_status = 'aguardando'
   where id = p_id;
end;
$$;

create or replace function public.justificar_excedente(p_id bigint, p_motivo text, p_justificativa text)
returns void language sql security invoker set search_path = ''
as $$ select privado.justificar_excedente(p_id, p_motivo, p_justificativa) $$;

revoke all on function public.justificar_excedente(bigint, text, text) from public, anon;
revoke all on function privado.justificar_excedente(bigint, text, text) from public, anon;
grant execute on function public.justificar_excedente(bigint, text, text) to authenticated;
grant execute on function privado.justificar_excedente(bigint, text, text) to authenticated;
