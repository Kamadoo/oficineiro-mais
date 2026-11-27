const test = require('node:test');
const assert = require('node:assert/strict');
const { carregar } = require('./carregar');

const Q = carregar(['qr.js']).FSM_QR;

const ECC_POR_BLOCO = [0, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26];
const BLOCOS = [0, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5];
const MASCARAS = [
  (x, y) => (x + y) % 2 === 0,
  (x, y) => y % 2 === 0,
  x => x % 3 === 0,
  (x, y) => (x + y) % 3 === 0,
  (x, y) => (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0,
  (x, y) => ((x * y) % 2) + ((x * y) % 3) === 0,
  (x, y) => (((x * y) % 2) + ((x * y) % 3)) % 2 === 0,
  (x, y) => (((x + y) % 2) + ((x * y) % 3)) % 2 === 0
];

const multiplicar = (x, y) => {
  let z = 0;
  for (let i = 7; i >= 0; i--) {
    z = (z << 1) ^ ((z >>> 7) * 0x11d);
    z ^= ((y >>> i) & 1) * x;
  }
  return z & 0xff;
};

const avaliarPolinomio = (codigos, ponto) => codigos.reduce((soma, c) => multiplicar(soma, ponto) ^ c, 0);

function ler(modulos) {
  const tamanho = modulos.length,
    versao = (tamanho - 17) / 4;
  let formato = 0;
  for (let i = 14; i >= 9; i--) formato = (formato << 1) | (modulos[8][14 - i] ? 1 : 0);
  formato = (formato << 1) | (modulos[8][7] ? 1 : 0);
  formato = (formato << 1) | (modulos[8][8] ? 1 : 0);
  formato = (formato << 1) | (modulos[7][8] ? 1 : 0);
  for (let i = 5; i >= 0; i--) formato = (formato << 1) | (modulos[i][8] ? 1 : 0);
  formato ^= 0x5412;
  const nivel = formato >>> 13,
    mascara = (formato >>> 10) & 7;
  const funcao = Array.from({ length: tamanho }, () => new Array(tamanho).fill(false));
  for (let i = 0; i < tamanho; i++) funcao[6][i] = funcao[i][6] = true;
  for (let y = 0; y < 9; y++)
    for (let x = 0; x < 9; x++) {
      funcao[y][x] = true;
      if (x < 8) funcao[y][tamanho - 1 - x] = true;
      if (y < 8) funcao[tamanho - 1 - y][x] = true;
    }
  funcao[tamanho - 8][8] = true;
  if (versao > 1) {
    const quantidade = Math.floor(versao / 7) + 2,
      passo = Math.floor((versao * 8 + quantidade * 3 + 5) / (quantidade * 4 - 4)) * 2,
      posicoes = [6];
    for (let p = tamanho - 7; posicoes.length < quantidade; p -= passo) posicoes.splice(1, 0, p);
    posicoes.forEach((ay, i) =>
      posicoes.forEach((ax, j) => {
        const ultimo = posicoes.length - 1;
        if ((i === 0 && j === 0) || (i === 0 && j === ultimo) || (i === ultimo && j === 0)) return;
        for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) funcao[ay + dy][ax + dx] = true;
      })
    );
  }
  if (versao >= 7)
    for (let i = 0; i < 18; i++) {
      const a = tamanho - 11 + (i % 3),
        b = Math.floor(i / 3);
      funcao[b][a] = funcao[a][b] = true;
    }
  const bits = [];
  for (let direita = tamanho - 1; direita >= 1; direita -= 2) {
    if (direita === 6) direita = 5;
    for (let vertical = 0; vertical < tamanho; vertical++)
      for (let j = 0; j < 2; j++) {
        const x = direita - j,
          y = ((direita + 1) & 2) === 0 ? tamanho - 1 - vertical : vertical;
        if (!funcao[y][x]) bits.push(modulos[y][x] !== MASCARAS[mascara](x, y) ? 1 : 0);
      }
  }
  const codigos = [];
  for (let i = 0; i + 8 <= bits.length; i += 8) codigos.push(bits.slice(i, i + 8).reduce((a, b) => (a << 1) | b, 0));
  const quantidade = BLOCOS[versao],
    ecc = ECC_POR_BLOCO[versao],
    curtos = quantidade - (codigos.length % quantidade),
    tamanhoCurto = Math.floor(codigos.length / quantidade),
    blocos = Array.from({ length: quantidade }, () => new Array(tamanhoCurto + 1));
  let k = 0;
  for (let i = 0; i < tamanhoCurto + 1; i++)
    for (let j = 0; j < quantidade; j++) {
      if (i === tamanhoCurto - ecc && j < curtos) continue;
      blocos[j][i] = codigos[k++];
    }
  const dados = [];
  blocos.forEach((bloco, j) => {
    const corrigido =
      j < curtos ? bloco.slice(0, tamanhoCurto - ecc).concat(bloco.slice(tamanhoCurto - ecc + 1)) : bloco;
    let raiz = 1;
    for (let i = 0; i < ecc; i++) {
      assert.equal(avaliarPolinomio(corrigido, raiz), 0, 'síndrome do bloco ' + j);
      raiz = multiplicar(raiz, 2);
    }
    dados.push(...corrigido.slice(0, corrigido.length - ecc));
  });
  const fluxo = dados.flatMap(b => [7, 6, 5, 4, 3, 2, 1, 0].map(i => (b >>> i) & 1));
  const lerBits = (inicio, n) => fluxo.slice(inicio, inicio + n).reduce((a, b) => (a << 1) | b, 0);
  const tamanhoDoContador = versao < 10 ? 8 : 16;
  assert.equal(lerBits(0, 4), 4, 'modo byte');
  const n = lerBits(4, tamanhoDoContador);
  const bytes = [];
  for (let i = 0; i < n; i++) bytes.push(lerBits(4 + tamanhoDoContador + i * 8, 8));
  return { versao, nivel, mascara, texto: new TextDecoder().decode(Uint8Array.from(bytes)) };
}

test('o código lido de volta traz o mesmo texto, nível M e correção de erros válida', () => {
  const textos = [
    'a',
    'https://oficineiromais.com.br/',
    'https://exemplo.com.br/caminho/para/a/tela/de/presenca',
    'Presença na escola · Ação',
    'x'.repeat(150),
    'y'.repeat(200)
  ];
  for (const texto of textos) {
    const lido = ler(Q.matriz(texto));
    assert.equal(lido.texto, texto);
    assert.equal(lido.nivel, 0);
  }
});

test('todas as máscaras geram código legível', () => {
  for (let mascara = 0; mascara < 8; mascara++) {
    const lido = ler(Q.matriz('https://oficineiromais.com.br/', mascara));
    assert.equal(lido.mascara, mascara);
    assert.equal(lido.texto, 'https://oficineiromais.com.br/');
  }
});

test('o desenho tem margem, caixa quadrada e só retângulos', () => {
  const desenho = Q.desenho('https://oficineiromais.com.br/');
  assert.equal(desenho.tamanho, 29 + 8);
  assert.match(desenho.caminho, /^(M\d+ \d+h\d+v1h-\d+z)+$/);
  assert.equal(Q.desenho('z'.repeat(400)), null);
});
