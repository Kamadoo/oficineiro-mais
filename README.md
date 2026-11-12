<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="public/brand/oficineiromais-logo-negativo-transparente.svg">
    <img src="public/brand/oficineiromais-logo.svg" alt="Oficineiro+" width="320">
  </picture>
</p>

<p align="center">
  Gestão das oficinas de tecnologia educacional nas escolas da rede municipal.
</p>

<p align="center">
  <a href="https://github.com/Kamadoo/oficineiro-mais/actions/workflows/ci.yml"><img src="https://github.com/Kamadoo/oficineiro-mais/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/PostgreSQL-Supabase-3ECF8E?logo=supabase&logoColor=white" alt="Supabase">
  <img src="https://img.shields.io/badge/React-18-61DAFB?logo=react&logoColor=black" alt="React 18">
  <img src="https://img.shields.io/badge/licen%C3%A7a-todos%20os%20direitos%20reservados-lightgrey" alt="Licença">
</p>

---

## Sobre

O Oficineiro+ acompanha o trabalho dos oficineiros que levam soluções de tecnologia educacional às escolas: presença na escola com conferência de localização, grade de aulas, registro de cada atividade, relatório mensal assinado, visitas de campo dos analistas e a gestão de contas e carteiras da rede.

Cada perfil vê apenas o que lhe cabe. As regras de acesso ficam no banco de dados, com Row Level Security em todas as tabelas, e cada operação sensível fica registrada em auditoria.

## Perfis

| Perfil | Responsabilidades |
| --- | --- |
| **Oficineiro** | Marca entrada, almoço e saída na escola; monta a grade semanal; registra as aulas; assina o espelho de ponto e envia o relatório do ciclo. |
| **Direção escolar** | Confirma ou contesta as aulas, valida a grade e decide as justificativas de presença da própria escola. |
| **Analista** | Registra visitas às escolas da carteira, acompanha a agenda, a jornada de uso e o onboarding. |
| **Coordenação** | Acompanha presença, produtividade, relatórios e contas do núcleo. |
| **Gerência de projetos** | Visão da rede inteira, agenda dos analistas, adoção, onboarding e cadastro de contas. |
| **Administração** | Escolas, turmas, carteiras, feriados, correções excepcionais e auditoria completa. |

São 6 perfis e 54 telas, com modo escuro e layout responsivo até 360 px.

## Telas

As capturas abaixo usam apenas dados fictícios.

<p align="center">
  <img src="docs/img/visao-geral.png" alt="Visão geral da rede, perfil Gerência de projetos" width="900">
</p>

<table>
  <tr>
    <td width="40%"><img src="docs/img/presenca-coordenacao.png" alt="Presença de hoje, perfil Coordenação"></td>
    <td width="40%"><img src="docs/img/presenca-oficineiro.png" alt="Registro de presença, perfil Oficineiro"></td>
    <td width="20%"><img src="docs/img/celular.png" alt="Registro de presença no celular"></td>
  </tr>
  <tr>
    <td align="center">Presença de hoje (coordenação)</td>
    <td align="center">Registro de presença com raio da escola</td>
    <td align="center">Celular</td>
  </tr>
</table>

<p align="center">
  <img src="docs/img/visao-geral-escuro.png" alt="Visão geral no tema escuro" width="900">
</p>

## Arquitetura

```mermaid
flowchart LR
    N[Navegador] -->|HTTPS, CSP estrita| S[Site estático<br/>Cloudflare Pages]
    N -->|PostgREST e RPC| B[(PostgreSQL<br/>Supabase)]
    N -->|login e primeiro acesso| F[Edge Functions<br/>acesso, admin-usuarios]
    F --> B
    B --> A[(Auditoria)]
```

- **Interface:** componentes declarativos (`.dc.html`) com modelo, estilo e lógica no mesmo arquivo, renderizados com React 18 por um runtime de componentes de terceiros. Cada perfil é um componente que compõe suas telas, o menu e o cabeçalho comuns.
- **Build:** `scripts/build.py` publica cada arquivo com hash no nome, calcula o hash do script inline para a CSP, confere o SHA-256 dos componentes de terceiros e interrompe a geração se encontrar dados pessoais.
- **Banco:** 57 migrações versionadas, funções privilegiadas isoladas no schema `privado` e expostas por invólucros em `public`, tarefas agendadas com `pg_cron`.
- **Funções de borda:** autenticação por usuário e senha, primeiro acesso por CPF ou CNPJ com código por e-mail e administração de contas, em TypeScript (Deno).

Detalhes em [docs/arquitetura.md](docs/arquitetura.md).

## Segurança

- Row Level Security em todas as tabelas; nenhuma permissão para visitantes.
- Autenticação em dois fatores (TOTP) obrigatória para todos os perfis.
- CPF e CNPJ cifrados no banco; as telas recebem apenas a forma mascarada, e a revelação é exclusiva da gerência e auditada.
- Presença conferida pela distância até a escola; as coordenadas não são armazenadas.
- CSP sem `unsafe-inline` para scripts, Subresource Integrity no React, HSTS, `frame-ancestors 'none'` e `Cross-Origin-Opener-Policy`.
- Tempo de resposta mínimo constante no login, contra enumeração de usuários.
- Auditoria de RLS, matriz de permissões das RPC por perfil e testes de escopo entre escolas e carteiras.

Detalhes em [docs/seguranca.md](docs/seguranca.md).

## Qualidade

- 664 asserções pgTAP cobrindo regras de negócio, permissões e fluxos de cada perfil (`supabase/tests`).
- Auditoria automática de RLS executada a cada push (`tests/security`).
- ESLint e Prettier no front-end.
- Integração contínua no GitHub Actions: lint, build, testes do banco e auditoria.

## Estrutura

```
src/
  index.dc.html        página de entrada e autenticação
  components/          perfis, telas, menu e cabeçalho
  lib/                 autenticação, base comum, planilhas, notificações, aparência
  styles/              folha de estilo comum com tema claro e escuro
  runtime/             runtime de componentes (terceiros)
public/                marca, ícones e manifesto
vendor/                React, Leaflet e fonte Inter, com hash conferido no build
supabase/
  migrations/          esquema, políticas de acesso e funções
  functions/           Edge Functions
  tests/database/      testes pgTAP
  scripts/             verificação de segurança e promoção de administrador
scripts/               build, servidor local e verificação de dados pessoais
tests/
  security/            auditoria de RLS, matriz de RPC e testes de escopo
  fixtures/            dados fictícios para os testes
docs/                  arquitetura e segurança
```

## Executando localmente

Requisitos: Python 3.10+, Node.js 20+ e a [CLI do Supabase](https://supabase.com/docs/guides/cli).

```bash
supabase start
cp src/config.example.js src/config.js
npm install
npm run build
npm run serve
```

## Licença

Copyright (c) 2026 João Vitor Nunes. Todos os direitos reservados. Este repositório é público apenas para consulta; ver [LICENSE](LICENSE).
