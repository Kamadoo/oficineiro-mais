create type public.papel as enum ('gerente', 'coordenador', 'analista', 'direcao', 'oficineiro');

create table public.carteiras (
  id      text primary key check (id ~ '^[A-Z]{2,3}\d{1,2}$'),
  rotulo  text not null check (length(rotulo) between 1 and 80)
);

create table public.escolas (
  id          smallint generated always as identity primary key,
  sigla       text not null unique check (length(sigla) between 1 and 8),
  nome        text not null check (length(nome) between 3 and 160),
  endereco    text check (length(endereco) <= 200),
  carteira_id text references public.carteiras (id),
  latitude    double precision check (latitude between -90 and 90),
  longitude   double precision check (longitude between -180 and 180),
  raio_m      smallint not null default 80 check (raio_m between 20 and 500),
  ativa       boolean not null default true
);

create table public.perfis (
  id          uuid primary key references auth.users (id) on delete cascade,
  nome        text not null check (length(nome) between 3 and 120),
  papel       public.papel not null,
  escola_id   smallint references public.escolas (id),
  carteira_id text references public.carteiras (id),
  turno       text check (turno in ('manha', 'tarde', 'integral')),
  ativo       boolean not null default true,
  criado_em   timestamptz not null default now(),
  constraint escopo_por_papel check (
    (papel in ('oficineiro', 'direcao') and escola_id is not null and carteira_id is null) or
    (papel = 'analista' and carteira_id is not null and escola_id is null) or
    (papel in ('gerente', 'coordenador') and escola_id is null and carteira_id is null)
  )
);
create index on public.perfis (escola_id) where escola_id is not null;
create index on public.perfis (carteira_id) where carteira_id is not null;

create table public.jornada_pessoas (
  id                bigint generated always as identity primary key,
  escola_id         smallint not null references public.escolas (id),
  nome              text not null check (length(nome) between 2 and 160),
  tipo              char(1) not null check (tipo in ('A', 'P', 'S')),
  ano_escolar       smallint not null default 0 check (ano_escolar between 0 and 9),
  dias_sem_acesso   integer not null check (dias_sem_acesso >= -1),
  dias_acesso       integer not null check (dias_acesso >= 0),
  responsavel_turma text check (length(responsavel_turma) <= 160),
  base_ref          date not null
);
create index on public.jornada_pessoas (escola_id, base_ref);

create table public.presencas (
  id                 bigint generated always as identity primary key,
  oficineiro_id      uuid not null references public.perfis (id),
  escola_id          smallint not null references public.escolas (id),
  data               date not null,
  inicio             timestamptz not null,
  fim                timestamptz,
  distancia_inicio_m integer check (distancia_inicio_m >= 0),
  distancia_fim_m    integer check (distancia_fim_m >= 0),
  conferencia        text check (conferencia in ('Fora do raio', 'Sem encerramento', 'Enviado sem internet', 'Sem localização')),
  excedente_min      integer not null default 0 check (excedente_min >= 0),
  excedente_status   text not null default 'dentro' check (excedente_status in ('dentro', 'pendente', 'aguardando', 'autorizado', 'nao')),
  motivo             text check (length(motivo) <= 120),
  justificativa      text check (length(justificativa) <= 1000),
  decidido_por       uuid references public.perfis (id),
  decidido_em        timestamptz,
  unique (oficineiro_id, data),
  check (fim is null or fim > inicio)
);
create index on public.presencas (escola_id, data);

create table public.aulas_registro (
  id            bigint generated always as identity primary key,
  oficineiro_id uuid not null references public.perfis (id),
  escola_id     smallint not null references public.escolas (id),
  data          date not null,
  inicio        time not null,
  fim           time not null,
  turma         text not null check (length(turma) between 1 and 40),
  tipo          char(1) not null check (tipo in ('R', 'C', 'P')),
  solucao       text check (length(solucao) <= 80),
  presentes     smallint check (presentes >= 0),
  matriculados  smallint check (matriculados >= 0),
  situacao      text not null check (situacao in ('Realizada', 'Realizada parcialmente', 'Não realizada', 'Pendente de registro', 'Devolvido para ajuste', 'Revisado')),
  motivo        text check (length(motivo) <= 200),
  conteudo      text check (length(conteudo) <= 2000),
  check_direcao text check (check_direcao in ('ok', 'contestada')),
  check_motivo  text check (length(check_motivo) <= 500),
  check_por     uuid references public.perfis (id),
  check_em      timestamptz,
  criado_em     timestamptz not null default now(),
  check (fim > inicio),
  check (presentes is null or matriculados is null or presentes <= matriculados),
  unique (oficineiro_id, data, inicio)
);
create index on public.aulas_registro (escola_id, data);

create table public.relatorios_mensais (
  id               bigint generated always as identity primary key,
  oficineiro_id    uuid not null references public.perfis (id),
  escola_id        smallint not null references public.escolas (id),
  competencia      date not null check (extract(day from competencia) = 1),
  status           text not null default 'fechado' check (status in ('fechado', 'aprovado_direcao', 'devolvido', 'aprovado_coordenacao')),
  fechado_em       timestamptz not null default now(),
  direcao_por      uuid references public.perfis (id),
  direcao_em       timestamptz,
  coordenacao_por  uuid references public.perfis (id),
  coordenacao_em   timestamptz,
  motivo_devolucao text check (length(motivo_devolucao) <= 1000),
  unique (oficineiro_id, competencia)
);

create table public.visitas (
  id            bigint generated always as identity primary key,
  analista_id   uuid not null references public.perfis (id),
  escola_id     smallint not null references public.escolas (id),
  data          date not null,
  tipo          text not null check (tipo in ('Suporte', 'Implantação', 'Acompanhamento', 'Formação')),
  subtipo       text check (length(subtipo) <= 80),
  participantes text check (length(participantes) <= 500),
  solucao       text check (length(solucao) <= 80),
  observacao    text check (length(observacao) <= 2000),
  criado_em     timestamptz not null default now()
);
create index on public.visitas (escola_id, data);

create table public.onboarding_os (
  id          text primary key check (id ~ '^[A-Z]{3,6}-\d{1,5}$'),
  numero      text not null,
  secretaria  text not null check (secretaria in ('SEMED', 'SEMAD', 'SEMSA')),
  arquivo     text check (length(arquivo) <= 200),
  recebida_em date not null,
  importada_por uuid references public.perfis (id),
  importada_em  timestamptz not null default now()
);

create table public.onboarding_itens (
  id               bigint generated always as identity primary key,
  os_id            text not null references public.onboarding_os (id) on delete cascade,
  nome             text not null check (length(nome) between 3 and 160),
  email            text check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' and length(email) <= 160),
  cpf_cifrado      bytea not null,
  cpf_hash         bytea not null,
  cpf_mascara      text not null,
  matricula        text check (length(matricula) <= 20),
  cargo            text check (length(cargo) <= 80),
  tipo             text check (length(tipo) <= 40),
  lotacao_original text check (length(lotacao_original) <= 200),
  escola_id        smallint references public.escolas (id),
  carteira_id      text references public.carteiras (id),
  status           text not null default 'pendente' check (status in ('pendente', 'concluido')),
  baixa_data       date,
  baixa_forma      text check (length(baixa_forma) <= 80),
  baixa_obs        text check (length(baixa_obs) <= 1000),
  baixa_por        uuid references public.perfis (id),
  unique (os_id, cpf_hash)
);
create index on public.onboarding_itens (carteira_id, status);
create index on public.onboarding_itens (cpf_hash);

do $$
declare t record;
begin
  for t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'public' and c.relkind = 'r' loop
    execute format('alter table public.%I enable row level security', t.relname);
  end loop;
end $$;
alter table auditoria.eventos enable row level security;
