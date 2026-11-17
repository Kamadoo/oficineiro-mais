const { spawnSync } = require('child_process');
const path = require('path');

const RAIZ = path.join(__dirname, '..');
const FUNCOES = path.join(RAIZ, 'supabase', 'functions');
const WIN = process.platform === 'win32';

function temDeno() {
  return spawnSync('deno', ['--version'], { shell: WIN, stdio: 'ignore' }).status === 0;
}

const deno = temDeno() ? ['deno'] : ['npx', '-y', 'deno@2'];

const etapas = [
  ['lint', ['npm', 'run', '-s', 'lint'], RAIZ],
  ['formatação', ['npm', 'run', '-s', 'format:check'], RAIZ],
  ['unitários', ['npm', 'test', '--silent'], RAIZ],
  ['funções: formatação', [...deno, 'fmt', '--check'], FUNCOES],
  ['funções: lint', [...deno, 'lint'], FUNCOES],
  ['funções: testes', [...deno, 'test', '-A', 'tests/'], FUNCOES]
];

const ESC = new RegExp(String.fromCharCode(27) + '\\[[0-9;]*m', 'g');
const limpar = t => String(t || '').replace(ESC, '');

function resumo(nome, saida) {
  const linhas = limpar(saida).split(/\r?\n/);
  if (nome === 'unitários') {
    const p = linhas.find(l => /^ℹ pass /.test(l));
    const f = linhas.find(l => /^ℹ fail /.test(l));
    if (p && f) return p.replace('ℹ ', '') + ', ' + f.replace('ℹ ', '');
  }
  if (nome === 'funções: testes') {
    const l = linhas.find(x => /\d+ passed \| \d+ failed/.test(x));
    if (l)
      return l
        .replace(/^\s*(ok|FAILED)\s*\|\s*/, '')
        .replace(/\s*\(.*$/, '')
        .trim();
  }
  return '';
}

let falhou = 0;
for (const [nome, [cmd, ...args], cwd] of etapas) {
  const inicio = Date.now();
  const r = spawnSync(cmd, args, { cwd, shell: WIN, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  const s = ((Date.now() - inicio) / 1000).toFixed(0) + ' s';
  const saida = (r.stdout || '') + (r.stderr || '');
  if (r.status === 0) {
    const extra = resumo(nome, saida);
    console.log('ok    ' + nome + ' (' + s + ')' + (extra ? ': ' + extra : ''));
    continue;
  }
  falhou++;
  console.log('FALHA ' + nome + ' (' + s + ')');
  const linhas = limpar(saida)
    .split(/\r?\n/)
    .filter(l => l.trim());
  const relevantes = linhas.filter(l => /error|erro|fail|falh|✖|not ok|assert|warning/i.test(l));
  for (const l of (relevantes.length ? relevantes : linhas).slice(-15)) console.log('      ' + l);
}

console.log(falhou ? falhou + ' etapa(s) com falha' : 'tudo certo');
process.exit(falhou ? 1 : 0);
