# Segurança

## Princípios

- O banco é a fronteira de segurança. A interface nunca é tratada como confiável: toda leitura e escrita passa por políticas de Row Level Security ou por funções que validam perfil e escopo.
- Menor privilégio. Visitantes não têm permissão em nenhuma tabela ou função; usuários autenticados acessam apenas invólucros em `public`; a lógica sensível fica em `privado`.
- Dados pessoais mínimos. O sistema guarda só o necessário para a operação e expõe ainda menos.

## Autenticação

- Login por usuário e senha pela Edge Function `acesso`, com tempo mínimo de resposta constante para não revelar se o usuário existe.
- Primeiro acesso por CPF ou CNPJ e código enviado por e-mail; o nome de usuário é gerado a partir do cargo e do nome.
- Senha com no mínimo 12 caracteres, letras maiúsculas e minúsculas, números e símbolos.
- Segundo fator (TOTP) obrigatório: sem nível de garantia `aal2`, as políticas não entregam nenhum dado.
- Sessão com limite de duração; troca de senha encerra as sessões nos outros aparelhos.

## Autorização

| Perfil | Escopo dos dados |
| --- | --- |
| Oficineiro | próprios registros e a própria escola, sem dados de alunos |
| Direção | a própria escola, sem dados de alunos da jornada de uso |
| Analista | escolas da própria carteira |
| Coordenação e gerência | a rede inteira |
| Administração | a rede inteira e as configurações do sistema |

O escopo é calculado no banco a partir do perfil do usuário autenticado, nunca a partir de parâmetros enviados pelo navegador.

## Dados pessoais

- CPF e CNPJ cifrados em repouso; a API devolve apenas a forma mascarada (`***.456.789-**`). A revelação completa é uma função exclusiva da gerência e fica registrada na auditoria.
- A presença guarda a distância até a escola e a precisão informada pelo aparelho, não as coordenadas.
- O registro de atividades não guarda IP nem localização.
- Contas removidas têm nome, documento, e-mail e telefone apagados; os registros históricos permanecem anonimizados. Contas desativadas há mais de 30 dias são removidas automaticamente.
- O build recusa a publicação de qualquer arquivo com CPF válido, e-mail real ou nome de uma base de referência.

## Auditoria

Gatilhos em todas as tabelas de negócio registram quem alterou o quê e quando. O registro de atividades acrescenta entradas no sistema, consultas a dados de outras pessoas, exportações, impressões e tentativas de presença recusadas.

## Navegador

| Cabeçalho | Valor |
| --- | --- |
| `Content-Security-Policy` | `default-src 'self'`; scripts só do próprio site e do hash do mapa de recursos, sem `unsafe-inline`; `object-src 'none'`; `base-uri 'none'`; `form-action 'none'`; `frame-ancestors 'none'` |
| `Strict-Transport-Security` | `max-age=31536000` |
| `Cross-Origin-Opener-Policy` | `same-origin` |
| `X-Frame-Options` | `DENY` |
| `Referrer-Policy` | `no-referrer` |
| `Permissions-Policy` | geolocalização só no próprio site; câmera e microfone bloqueados |

O React é carregado com Subresource Integrity, e todos os arquivos de terceiros têm o SHA-256 conferido no build. Conteúdo vindo do banco nunca é interpretado como HTML. O código do site não usa `innerHTML`; o runtime de componentes usa `innerHTML` só para compilar os modelos dos próprios arquivos `.dc.html`, publicados pelo build com hash no nome, e os valores do banco entram nos modelos por interpolação, que o React escapa.

## Verificação

- `supabase/tests/database`: testes pgTAP de permissão para cada perfil.
- `tests/security/rls_audit.py`: tenta ler e escrever em todas as tabelas como visitante, como usuário sem MFA e como cada perfil, e falha se algum acesso indevido for aceito.
- `tests/security/rpc_matrix.py`: monta a matriz de quais perfis conseguem executar cada função exposta.
- `tests/security/scope_audit.py`: tenta acessar outra escola ou carteira, injetar SQL e escalar privilégios.
- `supabase/scripts/verificar_seguranca.sql`: checagem do projeto em produção (RLS, permissões, funções expostas).
