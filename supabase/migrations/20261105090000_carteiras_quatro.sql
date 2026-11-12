update public.escolas e
   set carteira_id = m.carteira
  from (values
    ('Alt', 'CS1'), ('Mdf', 'CS1'), ('Udn', 'CS1'), ('Mctc', 'CS1'), ('Ncsr', 'CS1'), ('Pcm', 'CS1'),
    ('Mlss', 'CS1'), ('Nrd', 'CS1'), ('Cle', 'CS1'), ('Mj', 'CS1'), ('Ansee', 'CS1'), ('Chr', 'CS1'), ('Orc', 'CS1'),
    ('Bpr', 'CS2'), ('Ves', 'CS2'), ('Rcl', 'CS2'), ('Vwd', 'CS2'), ('Jfs', 'CS2'),
    ('Fwd', 'CS3'), ('Dads', 'CS3'), ('El', 'CS3'), ('Dcg', 'CS3'), ('Df', 'CS3'),
    ('Em', 'CS4'), ('Jbd', 'CS4'), ('Cr', 'CS4'), ('Dsj', 'CS4'), ('Cm', 'CS4'), ('Hj', 'CS4'),
    ('Sede', 'AT1')
  ) as m(sigla, carteira)
 where e.sigla = m.sigla and e.carteira_id is distinct from m.carteira
   and exists (select 1 from public.carteiras c where c.id = m.carteira);

do $$
declare
  n integer;
begin
  update public.escolas set carteira_id = null where carteira_id in ('CS5', 'CS6');
  select count(*) into n from public.perfis where carteira_id in ('CS5', 'CS6');
  if n = 0 then
    update public.onboarding_itens set carteira_id = null where carteira_id in ('CS5', 'CS6');
    delete from public.carteiras where id in ('CS5', 'CS6');
  else
    raise notice '% analista(s) ainda estão nas carteiras CS5 ou CS6. Mude a carteira em Gestão de Contas, Administração da conta, Alterar perfil, e rode este arquivo de novo.', n;
  end if;
end $$;
