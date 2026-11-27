create or replace function privado.registro_na_presenca()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_ini timestamptz;
  v_fim timestamptz;
  v_p public.presencas;
begin
  if auth.uid() is null or auth.uid() <> new.oficineiro_id then return null; end if;
  if new.situacao not in ('Realizada', 'Realizada parcialmente') then return null; end if;
  if tg_op = 'UPDATE' and old.situacao in ('Realizada', 'Realizada parcialmente')
     and old.data = new.data and old.inicio = new.inicio and old.fim = new.fim then
    return null;
  end if;
  v_ini := (new.data + new.inicio) at time zone 'America/Sao_Paulo';
  v_fim := (new.data + new.fim) at time zone 'America/Sao_Paulo';
  select * into v_p from public.presencas p
   where p.oficineiro_id = new.oficineiro_id and p.data = new.data
     and p.inicio <= v_ini + interval '15 minutes'
     and coalesce(p.fim, greatest(now(), v_fim)) >= v_fim
   order by p.inicio
   limit 1;
  if v_p.id is null then
    perform privado.invalido('a atividade só pode ser registrada como realizada se você estava com a presença iniciada na escola nesse horário (até 15 minutos depois do início da atividade)');
  end if;
  if v_p.pausa_inicio is not null and v_fim > v_p.pausa_inicio
     and v_ini < coalesce(v_p.pausa_fim, 'infinity'::timestamptz) then
    perform privado.invalido('a atividade não pode ser registrada dentro do intervalo da pausa para almoço');
  end if;
  return null;
end;
$$;

revoke all on function privado.registro_na_presenca() from public, anon, authenticated;
