begin;

do $$
declare
  v_login text := 'SEU-LOGIN';
  v public.perfis;
begin
  if not exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
                  where t.typname = 'papel' and e.enumlabel = 'administrador') then
    raise exception 'Rode antes o 37_perfil_administrador.sql.';
  end if;
  if v_login = 'SEU' || '-LOGIN' or trim(v_login) = '' then
    raise exception 'Troque SEU-LOGIN pelo login da conta que vai virar administradora antes de rodar.';
  end if;
  select * into v from public.perfis where usuario = lower(trim(v_login));
  if v.id is null then
    raise exception 'Login % não encontrado. A conta precisa existir e já ter feito o primeiro acesso.', v_login;
  end if;
  if not v.ativo then
    raise exception 'A conta % está desativada.', v_login;
  end if;
  update public.mudancas_escola set cancelada_em = now()
   where usuario_id = v.id and aplicada_em is null and cancelada_em is null;
  update public.perfis
     set papel = 'administrador', escola_id = null, carteira_id = null, jornada_inicio = null
   where id = v.id;
  perform auditoria.registrar('PROMOVER_ADMINISTRADOR', 'perfis', v.id::text,
    jsonb_build_object('papel', jsonb_build_object('de', v.papel::text, 'para', 'administrador')));
end $$;

select nome, usuario, papel::text as perfil, ativo
  from public.perfis
 where papel::text = 'administrador'
 order by nome;

commit;
