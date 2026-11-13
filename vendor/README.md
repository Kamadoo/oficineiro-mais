# Código de terceiros

Os arquivos desta pasta não são editados no projeto. O build (`scripts/build.py`) confere o SHA-256 de cada um e recusa a geração se algum tiver sido alterado; o React também leva Subresource Integrity na página.

| Pasta | Conteúdo | Versão | Licença |
| --- | --- | --- | --- |
| `dc-runtime/` | runtime dos componentes `.dc.html` | sem número de versão no arquivo | não declarada no arquivo |
| `react/` | React e React DOM, builds de produção UMD | 18.3.1 | MIT |
| `leaflet/` | Leaflet, mapas das escolas | 1.9.4 | BSD-2-Clause |
| `fonts/inter/` | fonte Inter em WOFF, pesos usados pelo site | — | SIL Open Font License 1.1 (`OFL.txt`) |

## Runtime de componentes

`dc-runtime/dc-runtime.js` é o runtime que acompanha os arquivos `.dc.html` exportados pela ferramenta de prototipação usada no início do projeto. Ele lê o modelo, o estilo e a lógica de cada componente, compila o modelo e o renderiza com o React de `react/`. Funcionamento e limites estão em [`docs/arquitetura.md`](../docs/arquitetura.md).

Diferenças em relação ao arquivo original:

- `COMPONENT_DIR` aponta para `./components`, a pasta dos componentes publicada pelo build;
- os comentários do gerador foram retirados.

O arquivo também contém endereços do React, do React DOM e do Babel em `unpkg.com`. Esses caminhos não são usados: o React é carregado pela página antes do runtime, o Babel só seria buscado para módulos externos em JSX, que o projeto não tem, e a CSP (`script-src 'self'`) bloquearia qualquer script externo. Eles ficam no arquivo para não alterar o código de terceiros.
