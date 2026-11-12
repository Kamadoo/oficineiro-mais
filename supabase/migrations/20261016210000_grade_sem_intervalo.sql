alter table public.grade_aulas disable trigger grade_sem_conflito;
alter table public.grade_aulas disable trigger grade_alterada;

update public.grade_aulas
   set inicio = case when inicio in ('09:50', '10:40', '15:50', '16:40') then inicio - interval '20 minutes' else inicio end,
       fim    = case when fim in ('10:40', '11:30', '16:40', '17:30') then fim - interval '20 minutes' else fim end
 where inicio in ('09:50', '10:40', '15:50', '16:40')
    or fim in ('10:40', '11:30', '16:40', '17:30');

alter table public.grade_aulas enable trigger grade_sem_conflito;
alter table public.grade_aulas enable trigger grade_alterada;
