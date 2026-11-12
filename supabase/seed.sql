insert into public.carteiras (id, rotulo) values
  ('AT1', 'AT1'),
  ('CS1', 'CS1'),
  ('CS2', 'CS2'),
  ('CS3', 'CS3'),
  ('CS4', 'CS4')
on conflict (id) do nothing;

insert into public.escolas (sigla, nome, endereco, carteira_id) values
  ('Ebv', 'Ebv - Cei Bem-te-vi', 'Rua das Andorinhas, 120 - Jardim Primavera', 'CS1'),
  ('Ejp', 'Ejp - E. M. Jardim dos Ipês', 'Rua dos Ipês, 45 - Vila Nova', 'CS1'),
  ('Esf', 'Esf - E. M. Santa Fé', 'Avenida Central, 800 - Centro', 'CS1'),
  ('Ecl', 'Ecl - E. M. Colina Azul', 'Rua da Colina, 310 - Alto da Serra', 'CS2'),
  ('Erv', 'Erv - E. M. Rio Verde', 'Rua Beira-Rio, 77 - Ribeirão', 'CS2'),
  ('Epm', 'Epm - E. M. Pedra Moura', 'Estrada Velha, km 4 - Pedra Moura', 'CS3'),
  ('Elg', 'Elg - E. M. Lagoa Grande', 'Rua da Lagoa, 15 - Lagoa Grande', 'CS3'),
  ('Ecc', 'Ecc - E. M. Campo Claro', 'Rua das Flores, 230 - Campo Claro', 'CS4'),
  ('Eso', 'Eso - E. M. Sol Nascente', 'Rua do Sol, 500 - Sol Nascente', 'CS4'),
  ('Eva', 'Eva - E. M. Vale Alegre', 'Avenida do Vale, 1200 - Vale Alegre', 'CS4')
on conflict (sigla) do nothing;
