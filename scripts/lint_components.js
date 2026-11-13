const fs = require('fs');
const path = require('path');
const { ESLint } = require('eslint');
const prettier = require('prettier');

const RAIZ = path.resolve(__dirname, '..');
const PASTA = path.join(RAIZ, 'src', 'components');
const MARCA = '<script type="text/x-dc" data-dc-script>';
const formatar = process.argv.includes('--formatar');

function partes(texto) {
  const marca = texto.indexOf(MARCA);
  if (marca < 0) return null;
  const inicio = texto.indexOf('>', marca) + 1;
  const fim = texto.lastIndexOf('</script>');
  return { inicio, fim, script: texto.slice(inicio, fim), linha: texto.slice(0, inicio).split('\n').length - 1 };
}

async function principal() {
  const eslint = new ESLint({ cwd: RAIZ });
  const opcoes = { ...(await prettier.resolveConfig(path.join(RAIZ, '.prettierrc'))), parser: 'babel' };
  const arquivos = fs
    .readdirSync(PASTA)
    .filter(nome => nome.endsWith('.dc.html'))
    .sort();
  let problemas = 0;
  for (const nome of arquivos) {
    const caminho = path.join(PASTA, nome);
    const texto = fs.readFileSync(caminho, 'utf8');
    const p = partes(texto);
    if (!p) continue;
    const codigo = p.script.replace(/^\n/, '');
    const formatado = await prettier.format(codigo, opcoes);
    if (formatado !== codigo) {
      if (formatar) fs.writeFileSync(caminho, texto.slice(0, p.inicio) + '\n' + formatado + texto.slice(p.fim));
      else {
        problemas++;
        console.log(nome + ': script fora do padrão do Prettier (npm run format:components)');
      }
    }
    const [resultado] = await eslint.lintText(formatar ? formatado : codigo, {
      filePath: path.join(PASTA, nome.replace(/\.dc\.html$/, '.dc.js'))
    });
    for (const m of resultado.messages) {
      problemas++;
      console.log(nome + ':' + (m.line + p.linha + 1) + ' ' + (m.ruleId || '') + ' ' + m.message);
    }
  }
  if (problemas) {
    console.log(problemas + ' problema(s) em ' + arquivos.length + ' componentes');
    process.exit(1);
  }
  console.log(arquivos.length + ' componentes sem problemas');
}

principal().catch(erro => {
  console.error(erro);
  process.exit(1);
});
