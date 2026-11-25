const test = require('node:test');
const assert = require('node:assert/strict');
const { carregar } = require('./carregar');

const Contas = carregar(['base.js', 'contas.js']).FSM_CONTAS;

test('CPF válido e inválido', () => {
  assert.equal(Contas.documentoValido('529.982.247-25'), true);
  assert.equal(Contas.documentoValido('11144477735'), true);
  assert.equal(Contas.documentoValido('529.982.247-24'), false);
  assert.equal(Contas.documentoValido('111.111.111-11'), false);
  assert.equal(Contas.documentoValido('123'), false);
  assert.equal(Contas.documentoValido(''), false);
});

function cpfFicticio(base) {
  const d = base.split('').map(Number);
  [9, 10].forEach(n => d.push(((d.reduce((t, x, i) => t + x * (n + 1 - i), 0) * 10) % 11) % 10));
  return d.join('');
}

test('documento da planilha recupera o zero à esquerda apagado pelo Excel', () => {
  const um = cpfFicticio('012345678'),
    dois = cpfFicticio('001234567');
  assert.equal(Contas.documentoDaPlanilha(um.slice(1)), um);
  assert.equal(Contas.documentoDaPlanilha(Number(um)), um);
  assert.equal(Contas.documentoDaPlanilha(dois.slice(2)), dois);
  assert.equal(Contas.documentoDaPlanilha('529.982.247-25'), '52998224725');
  assert.equal(Contas.documentoDaPlanilha('11.222.333/0001-81'), '11222333000181');
  assert.equal(Contas.documentoDaPlanilha('', um.slice(1)), um);
  assert.equal(Contas.documentoDaPlanilha('52998224725', um.slice(1)), '52998224725');
  assert.equal(Contas.documentoDaPlanilha('52998224724', '11144477735'), '11144477735');
  assert.equal(Contas.documentoDaPlanilha('529.982.247-24', 'pum'), '52998224724');
  assert.equal(Contas.documentoDaPlanilha('123'), '123');
  assert.equal(Contas.documentoDaPlanilha('', null), '');
});

test('CNPJ válido e inválido', () => {
  assert.equal(Contas.documentoValido('11.222.333/0001-81'), true);
  assert.equal(Contas.documentoValido('11.222.333/0001-82'), false);
  assert.equal(Contas.documentoValido('00000000000000'), false);
});

test('documento mascarado', () => {
  assert.equal(Contas.documentoMascarado('529.982.247-25'), '***.982.247-**');
  assert.equal(Contas.documentoMascarado('11222333000181'), '**.***.333/0001-**');
  assert.equal(Contas.documentoMascarado('123'), 'inválido');
  assert.equal(Contas.documentoMascarado(''), '—');
});

test('detalhamento do lote de contas', () => {
  const nomes = { oficineiro: 'Oficineiro de Inclusão Digital' };
  const lote = {
    arquivo: 'lote.xlsx',
    linhas: [
      {
        n: 2,
        st: 'pronta',
        nome: 'Pessoa Um',
        email: 'um@exemplo.test',
        cpf: '52998224725',
        papel: 'oficineiro',
        escola: { sigla: 'Ebv' }
      },
      { n: 3, st: 'erro', erro: 'CPF inválido', nome: 'Pessoa Dois', papel: 'oficineiro' }
    ]
  };
  const detalhe = Contas.detalharLote(lote, nomes);
  assert.equal(detalhe.temArquivo, true);
  assert.equal(detalhe.resumo, 'lote.xlsx · 2 pessoas · 1 pronta · 1 com problema');
  assert.equal(detalhe.linhas[0].documento, '***.982.247-**');
  assert.equal(detalhe.linhas[0].vinculo, 'Ebv');
  assert.equal(detalhe.linhas[0].perfil, 'Oficineiro de Inclusão Digital');
  assert.equal(detalhe.linhas[1].situacao, 'CPF inválido');
  assert.equal(detalhe.botao, 'Criar 1 conta');
  assert.equal(detalhe.podeCriar, true);
  assert.equal(Contas.detalharLote(null, nomes).temArquivo, false);
});
